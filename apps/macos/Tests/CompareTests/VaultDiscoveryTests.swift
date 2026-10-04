import Foundation
import Testing
import CoreBridge
import CompareShared
@testable import CompareUI

@Suite struct VaultDiscoveryTests {
    @Test func homepageLinksAreNormalizedWithoutInventingMounts() throws {
        for base in ["https://uat.example.invalid", "http://uat.example.invalid"] {
            for suffix in ["/ui", "/ui/", "/"] {
                let link = try VaultLink.parse(base + suffix)
                #expect(link.origin == base)
                #expect(link.mount == nil && link.path == nil)
            }
        }
        #expect(throws: VaultFailure.self) { try VaultLink.parse("https://uat.example.invalid/ui/?redirect=external") }
    }

    @Test func nonHttpSchemeIsNotRejectedByUrlScopeValidation() throws {
        let link = try VaultLink.parse("vault://uat.example.invalid/ui/")
        #expect(link.origin == "vault://uat.example.invalid")
        #expect(link.mount == nil && link.path == nil)
    }
}

private func discoverySettings() -> VaultSettings {
    var settings = VaultSettings()
    settings.url = "https://uat.example.invalid/ui/"
    settings.token = "synthetic-token"
    settings.confirmedNonProduction = true
    return settings
}

actor DiscoveryFixture: VaultTransport {
    var requests: [URLRequest] = []
    let version: Int
    let deniedNamespaces: Bool
    let deniedDirectory: Bool
    let includeEmptyDirectory: Bool
    init(version: Int = 2, deniedNamespaces: Bool = false, deniedDirectory: Bool = false, includeEmptyDirectory: Bool = false) {
        self.version = version; self.deniedNamespaces = deniedNamespaces; self.deniedDirectory = deniedDirectory; self.includeEmptyDirectory = includeEmptyDirectory
    }
    func send(_ request: URLRequest) async throws -> VaultHTTPResponse {
        requests.append(request)
        let path = request.url!.path
        if path == "/v1/sys/internal/ui/mounts" {
            return vaultResponse(#"{"data":{"secret":{"FPMS-NT-V2/":{"type":"kv","options":{"version":"2"}},"database/":{"type":"database"},"prod-secrets/":{"type":"kv"}}}}"#)
        }
        if path == "/v1/sys/namespaces" {
            if deniedNamespaces { return vaultResponse(#"{"errors":["private server message"]}"#,status:403) }
            return vaultResponse(#"{"data":{"keys":["team-a/","team-b/","prod/"]}}"#)
        }
        if path == "/v1/sys/internal/ui/mounts/FPMS-NT-V2" {
            return vaultResponse("{\"data\":{\"path\":\"FPMS-NT-V2/\",\"type\":\"kv\",\"options\":{\"version\":\"" + String(version) + "\"}}}")
        }
        if path.hasPrefix("/v1/FPMS-NT-V2/"), request.url?.query == nil {
            let values = path.hasSuffix("qat-other") ? #"{"PORT":"3000","big":9007199254740993}"# : #"{"PORT":3000,"big":9007199254740993}"#
            return vaultResponse(version == 2 ? "{\"data\":{\"data\":" + values + "}}" : "{\"data\":" + values + "}")
        }
        let prefix = "/v1/FPMS-NT-V2" + (version == 2 ? "/metadata" : "")
        if path == prefix || path == prefix + "/" {
            let keys = includeEmptyDirectory ? #"["auth/","payment/","promotion/","empty/","prod/","root-config"]"# : #"["auth/","payment/","promotion/","prod/","root-config"]"#
            return vaultResponse(#"{"data":{"keys":PLACEHOLDER}}"#.replacingOccurrences(of: "PLACEHOLDER", with: keys))
        }
        if path == prefix + "/auth" { return vaultResponse(#"{"data":{"keys":["uat-swim","qat-other","nested/"]}}"#) }
        if path == prefix + "/auth/nested" { return vaultResponse(#"{"data":{"keys":["uat-swim","qat-other"]}}"#) }
        if path == prefix + "/payment" {
            if deniedDirectory { return vaultResponse(#"{"errors":["private secret"]}"#,status:403) }
            return vaultResponse(#"{"data":{"keys":["uat-swim","qat-other","production"]}}"#)
        }
        if path == prefix + "/promotion" { return vaultResponse(#"{"data":{"keys":["uat-swim","qat-other"]}}"#) }
        if path == prefix + "/empty" { return vaultResponse(#"{"data":{"keys":[]}}"#) }
        throw VaultFailure.invalid("Unexpected fixture route")
    }
}

extension VaultDiscoveryTests {
    @Test func namespaceQueryMismatchAndWhitespaceQueriesAreRejectedBeforeRequests() async throws {
        let transport = DiscoveryFixture(); let reader = VaultReader(transport: transport, validate: validatedFixture)
        var settings = discoverySettings()
        settings.url = "https://uat.example.invalid/ui/vault/secrets/FPMS-NT-V2/kv/auth%2Fuat-swim?namespace=team-a"
        await #expect(throws: VaultFailure.self) { try await reader.discoverConnection(settings) }
        settings.mount = "FPMS-NT-V2"; settings.environment = "uat-swim"
        #expect(throws: VaultFailure.self) { try VaultTarget(settings) }
        #expect(await transport.requests.isEmpty)
        for url in [" https://uat.example.invalid/ui/?redirect=external ",
                    "https://uat.example.invalid/ui/vault/secrets/FPMS-NT-V2/kv/auth%2Fuat-swim?namespace=team-a&namespace=team-b"] {
            #expect(throws: VaultFailure.self) { try VaultLink.parse(url) }
        }
        settings.namespace = "team-a"; settings.url += "/" // Namespace trailing slash is normalized.
        _ = try await reader.discoverConnection(settings)
        #expect((await transport.requests).allSatisfy { $0.value(forHTTPHeaderField: "X-Vault-Namespace") == "team-a/" })
    }
    @Test func connectionDiscoversKvChoicesWithoutMountOrConfigurationInput() async throws {
        let transport = DiscoveryFixture()
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        let catalog = try await reader.discoverConnection(discoverySettings())
        #expect(catalog.mounts == ["FPMS-NT-V2"])
        #expect(catalog.namespaces == ["", "team-a", "team-b"])
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "X-Vault-Token") == "synthetic-token" })
        #expect(!requests.contains { $0.url!.path.contains("/data/") || $0.url!.path.contains("/metadata") })
    }
    @Test func namespaceListDenialStillOffersCurrentNamespaceAndMounts() async throws {
        let reader = VaultReader(transport: DiscoveryFixture(deniedNamespaces: true), validate: validatedFixture)
        let catalog = try await reader.discoverConnection(discoverySettings())
        #expect(catalog.namespaces == [""] && catalog.mounts == ["FPMS-NT-V2"])
        #expect(catalog.namespaceListingUnavailable)
    }
    @Test func configurationChoicesAreDeduplicatedAndKeepDirectoryAssociations() async throws {
        for version in [1, 2] {
            let transport = DiscoveryFixture(version: version)
            let reader = VaultReader(transport: transport, validate: validatedFixture)
            var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"
            let contents = try await reader.discoverContents(settings)
            #expect(contents.configurations == ["qat-other", "root-config", "uat-swim"])
            #expect(contents.directories(for: "uat-swim") == ["auth", "auth/nested", "payment", "promotion"])
            #expect(contents.directories(for: "root-config") == ["."])
            let requests = await transport.requests
            #expect(requests.count == 6)
            #expect(!requests.contains { $0.url!.path.contains("/prod") || $0.url!.path.contains("/data/") })
            #expect(requests.dropFirst().allSatisfy { $0.url?.query == "list=true" })
        }
    }
    @Test func failedDirectoryListingNeverPublishesAPartialCatalog() async throws {
        let transport = DiscoveryFixture(deniedDirectory: true)
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"
        do { _ = try await reader.discoverContents(settings); Issue.record("Partial directory discovery must fail") }
        catch let failure as VaultFailure { #expect(failure.code == "VAULT_HTTP_403" && !failure.message.contains("private")) }
    }
    @Test func productionLabelsAreBlockedWithoutManualConfirmation() async throws {
        let transport = DiscoveryFixture()
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        var settings = discoverySettings(); settings.confirmedNonProduction = false
        let catalog = try await reader.discoverConnection(settings)
        #expect(catalog.mounts == ["FPMS-NT-V2"])
        let baseline = await transport.requests.count
        settings.url = "https://production.example.invalid/ui/"
        await #expect(throws: VaultFailure.self) { try await reader.discoverConnection(settings) }
        settings = discoverySettings(); settings.mount = "prod-secrets"
        await #expect(throws: VaultFailure.self) { try await reader.discoverContents(settings) }
        settings.mount = "FPMS-NT-V2"; settings.directory = "production"
        await #expect(throws: VaultFailure.self) { try await reader.discoverContents(settings) }
        #expect(await transport.requests.count == baseline)
    }
    @Test func manualLiteralDirectoryDoesNotScanSiblingDirectories() async throws {
        let transport = DiscoveryFixture()
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"; settings.directoryPattern = "auth"
        let contents = try await reader.discoverContents(settings)
        #expect(contents.configurations == ["qat-other", "uat-swim"])
        #expect(contents.directories(for: "uat-swim") == ["auth"])
        #expect(contents.configurations(forDirectory: "**").isEmpty)
        #expect(await transport.requests.count == 2)
    }
    @Test func rootOnlyDiscoveryCannotClaimAllDirectories() async throws {
        let reader = VaultReader(transport: DiscoveryFixture(), validate: validatedFixture)
        var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"; settings.directoryPattern = "."
        let contents = try await reader.discoverContents(settings)
        #expect(contents.directories == ["."])
        #expect(contents.configurations(forDirectory: "**").isEmpty)
        #expect(contents.validatedConfigurationName("root-config", forDirectory: "**").isEmpty)
    }
    @Test func allDirectoryScopeOffersOnlyNamesPresentInEveryDirectory() async throws {
        let reader = VaultReader(transport: DiscoveryFixture(), validate: validatedFixture)
        var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"
        let contents = try await reader.discoverContents(settings)
        #expect(contents.configurations(forDirectory: "auth") == ["qat-other", "uat-swim"])
        #expect(contents.configurations(forDirectory: "payment") == ["qat-other", "uat-swim"])
        #expect(contents.configurations(forDirectory: "**") == ["qat-other", "uat-swim"])
        #expect(!contents.configurations(forDirectory: "**").contains("root-config"))
    }
    @Test func allDirectoryScopeDropsNamesMissingFromAnyDiscoveredDirectory() {
        let contents = VaultContents(paths: [
            .init(name: "shared", directory: "auth"),
            .init(name: "auth-only", directory: "auth"),
            .init(name: "shared", directory: "payment"),
            .init(name: "payment-only", directory: "payment"),
            .init(name: "shared", directory: "promotion")
        ], excludedProduction: false)
        #expect(contents.configurations(forDirectory: "auth") == ["auth-only", "shared"])
        #expect(contents.configurations(forDirectory: "**") == ["shared"])
        #expect(contents.configurations(forDirectory: "**").contains("auth-only") == false)
    }
    @Test func allDirectoryScopeTreatsAnEmptyDiscoveredDirectoryAsHavingNoCommonNames() async throws {
        let reader = VaultReader(transport: DiscoveryFixture(includeEmptyDirectory: true), validate: validatedFixture)
        var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"
        let contents = try await reader.discoverContents(settings)
        #expect(contents.directories.contains("empty"))
        #expect(contents.configurations(forDirectory: "**").isEmpty)
    }
    @Test func scopeChangesClearOnlyInvalidConfigurationNames() {
        let contents = VaultContents(paths: [
            .init(name: "shared", directory: "auth"),
            .init(name: "auth-only", directory: "auth"),
            .init(name: "shared", directory: "payment")
        ], discoveredDirectories: ["auth", "payment"], discoveryDirectoryPattern: "**", excludedProduction: false)
        var settings = VaultSettings(); settings.environment = "auth-only"
        settings.updateDirectoryPattern("**", contents: contents)
        #expect(settings.environment.isEmpty)
        settings.environment = "shared"
        settings.updateDirectoryPattern("auth", contents: contents)
        #expect(settings.environment == "shared")
        settings.selectConfiguration("auth-only", contents: contents)
        #expect(settings.environment == "auth-only")
        settings.updateDirectoryPattern("payment", contents: contents)
        settings.selectConfiguration("auth-only", contents: contents)
        #expect(settings.environment.isEmpty)
        settings.updateMount("other")
        #expect(settings.environment.isEmpty && settings.directoryPattern == "**")
        settings.environment = "manual"
        settings.updateDirectory("nested")
        #expect(settings.environment.isEmpty)
        settings.environment = "manual"
        settings.updateNamespace("team-a")
        #expect(settings.namespace == "team-a" && settings.namespacePattern == "." && settings.environment.isEmpty)
        settings.environment = "manual"
        settings.updateNamespacePattern("team-*")
        #expect(settings.namespacePattern == "team-*" && settings.environment.isEmpty)
    }
}

@Suite(.serialized) @MainActor struct VaultDiscoveryWorkspaceTests {
    private func settle(_ model: Workspace) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!model.busy)
    }
    @Test func catalogsStayIndependentAndChangingTokenClearsOnlyItsOptions() async throws {
        let transport = DiscoveryFixture()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: transport, validate: $0) })
        model.tool = .vault; model.vaultA = discoverySettings(); model.vaultB = discoverySettings()
        model.discoverVault(side: true); try await settle(model)
        #expect(model.vaultCatalogA?.mounts == ["FPMS-NT-V2"] && model.vaultCatalogB == nil)
        model.discoverVault(side: false); try await settle(model)
        #expect(model.vaultCatalogB?.mounts == ["FPMS-NT-V2"])
        let old = model.vaultA; model.vaultA.token = "different-synthetic-token"
        model.vaultChanged(side: true, old: old, new: model.vaultA)
        #expect(model.vaultCatalogA == nil && model.vaultContentsA == nil)
        #expect(model.vaultCatalogB?.mounts == ["FPMS-NT-V2"])
        model.cancel()
    }
    @Test func mountChangeInvalidatesContentButRetainsConnectionChoices() async throws {
        let transport = DiscoveryFixture()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: transport, validate: $0) })
        model.tool = .vault; model.vaultA = discoverySettings()
        model.discoverVault(side: true); try await settle(model)
        model.vaultA.mount = "FPMS-NT-V2"
        model.discoverVault(side: true, contents: true); try await settle(model)
        #expect(model.vaultContentsA?.configurations == ["qat-other", "root-config", "uat-swim"])
        let old = model.vaultA; model.vaultA.mount = "other-kv"
        model.vaultChanged(side: true, old: old, new: model.vaultA)
        #expect(model.vaultContentsA == nil && model.vaultCatalogA?.mounts == ["FPMS-NT-V2"])
        #expect(model.vaultPlanA == nil && model.vaultPlanB == nil)
        model.cancel()
    }
    @Test func failedDiscoveryRetainsManualInputAndNeverCreatesAComparison() async throws {
        let transport = DiscoveryFixture(deniedDirectory: true)
        let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: transport, validate: $0) })
        model.tool = .vault; model.vaultA = discoverySettings(); model.vaultA.mount = "FPMS-NT-V2"; model.vaultA.environment = "manual-name"
        model.discoverVault(side: true, contents: true); try await settle(model)
        #expect(model.error && model.vaultContentsA == nil && model.summary == nil)
        #expect(model.vaultA.environment == "manual-name" && model.vaultA.token == "synthetic-token")
        model.cancel()
    }
}

extension VaultDiscoveryTests {
    @Test func allDirectoriesPreviewKeepsProductionSubtreesExcluded() async throws {
        let transport = DiscoveryFixture()
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"; settings.environment = "uat-swim"
        let plan = try await reader.preview(VaultTarget(settings))
        #expect(plan.secrets.map(\.path).sorted() == ["auth/nested/uat-swim", "auth/uat-swim", "payment/uat-swim", "promotion/uat-swim"])
        #expect(!((await transport.requests).contains { $0.url!.path.contains("/prod") }))
    }
    @Test func productionPathInAnExistingPlanCannotBeRead() async throws {
        let transport = DiscoveryFixture()
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"; settings.environment = "uat-swim"
        let plan = VaultPlan(target: try VaultTarget(settings), secrets: [.init(namespace: "", namespaceKey: ".", path: "production/uat-swim", directoryKey: "production", kvVersion: 2)], discoveredNamespaces: [""], created: Date())
        await #expect(throws: VaultFailure.self) { try await reader.capture(plan) }
        #expect(await transport.requests.isEmpty)
    }
    @Test func malformedOrDuplicateCatalogsAreNotChoices() async throws {
        for body in [#"{"data":{}}"#, #"{"data":{"secret":{"kv/":{"type":"kv"},"kv/":{"type":"kv"}}}}"#, #"{"data":{"secret":{"../kv/":{"type":"kv"}}}}"#] {
            let transport = MatrixVault { _, _ in vaultResponse(body) }
            let reader = VaultReader(transport: transport, validate: validatedFixture)
            await #expect(throws: (any Error).self) { try await reader.discoverConnection(discoverySettings()) }
            #expect(await transport.requests.count == 1)
        }
    }
    @Test func discoveryRejectsDynamicEnginesBeforeListingTheirPaths() async throws {
        let transport = MatrixVault { _, _ in vaultResponse(#"{"data":{"path":"FPMS-NT-V2/","type":"database"}}"#) }
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"
        await #expect(throws: VaultFailure.self) { try await reader.discoverContents(settings) }
        #expect(await transport.requests.count == 1)
    }
    @Test func requestBudgetCannotYieldATruncatedConfigurationList() async throws {
        let transport = MatrixVault { request, count in
            if count == 1 { return vaultResponse(#"{"data":{"path":"FPMS-NT-V2/","type":"kv","options":{"version":"2"}}}"#) }
            let keys = count == 2 ? (0..<500).map { "service-\($0)/" } : ["config"]
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["data": ["keys": keys]]))
        }
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"
        do { _ = try await reader.discoverContents(settings); Issue.record("Budget exhaustion must fail discovery") }
        catch let error as VaultFailure { #expect(error.code == "RESOURCE_LIMIT") }
        #expect(await transport.requests.count == 500)
    }
}

actor HeldCatalogTransport: VaultTransport {
    let fixture = DiscoveryFixture()
    var pending: CheckedContinuation<Void, Never>?
    var hold = true
    var waiting: Bool { pending != nil }
    func send(_ request: URLRequest) async throws -> VaultHTTPResponse {
        if hold {
            hold = false
            await withCheckedContinuation { pending = $0 }
        }
        return try await fixture.send(request)
    }
    func release() { let continuation = pending; pending = nil; continuation?.resume() }
}
extension VaultDiscoveryWorkspaceTests {
    @Test func selectingChildNamespaceExplainsReconfirmationAndReloadsOnlyThatScope() async throws {
        let transport = DiscoveryFixture()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: transport, validate: $0) })
        model.tool = .vault; model.vaultA = discoverySettings()
        model.discoverVault(side: true); try await settle(model)
        let old = model.vaultA; model.vaultA.namespace = "team-a"
        model.vaultChanged(side: true, old: old, new: model.vaultA)
        #expect(!model.vaultA.confirmedNonProduction && model.vaultCatalogA == nil)
        #expect(model.notice.contains("重新读取选项") && model.notice.contains("namespace"))
        model.vaultA.confirmedNonProduction = true
        model.discoverVault(side: true); try await settle(model)
        #expect(model.vaultCatalogA?.namespaces == ["team-a", "team-a/team-a", "team-a/team-b"])
        #expect((await transport.requests).suffix(2).allSatisfy { $0.value(forHTTPHeaderField: "X-Vault-Namespace") == "team-a/" })
        model.cancel()
    }
    @Test func browserNameHintDoesNotApplyToAnUnrelatedMountAndNamespaceCanBeUnpacked() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: DiscoveryFixture(), validate: $0) })
        model.tool = .vault; model.vaultA = discoverySettings(); model.vaultA.mount = "FPMS-NT-V2"
        model.vaultA.url = "https://uat.example.invalid/ui/vault/secrets/another-kv/kv/auth%2Fuat-swim"
        model.discoverVault(side: true, contents: true); try await settle(model)
        #expect(model.vaultContentsA?.configurations.contains("uat-swim") == true && model.vaultA.environment.isEmpty)
        model.vaultA.url += "?namespace=team-a%2Fnested%2F"
        model.unpackVaultLink(side: true)
        #expect(model.vaultA.namespace == "team-a/nested" && !model.vaultA.confirmedNonProduction)
        model.cancel()
    }
    @Test func staleSettingsGuardEndsLoadingNoticeWithoutPublishingOptions() async throws {
        let transport = HeldCatalogTransport()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: transport, validate: $0) })
        model.tool = .vault; model.vaultA = discoverySettings(); model.discoverVault(side: true)
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await transport.waiting), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(await transport.waiting)
        model.vaultA.token = "changed-without-onChange" // Exercise the exact-settings guard independently.
        await transport.release(); try await settle(model)
        #expect(model.vaultCatalogA == nil && model.notice.contains("重新读取选项"))
        model.cancel()
    }
    @Test func lateCatalogCannotUndoCancellationOrCredentialChanges() async throws {
        for cancel in [false, true] {
            let transport = HeldCatalogTransport()
            let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: transport, validate: $0) })
            model.tool = .vault; model.vaultA = discoverySettings()
            model.discoverVault(side: true)
            let deadline = ContinuousClock.now + .seconds(3)
            while !(await transport.waiting), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
            #expect(await transport.waiting)
            if cancel { model.cancel() }
            else {
                let old = model.vaultA; model.vaultA.token = "changed-synthetic-token"
                model.vaultChanged(side: true, old: old, new: model.vaultA)
            }
            await transport.release()
            try await Task.sleep(for: .milliseconds(30))
            #expect(!model.busy && model.vaultCatalogA == nil && model.vaultContentsA == nil && model.vaultPlanA == nil)
            model.discoverVault(side: true); try await settle(model)
            #expect(model.vaultCatalogA?.mounts == ["FPMS-NT-V2"] && !model.error)
            model.cancel()
        }
    }
}

extension VaultDiscoveryTests {
    @Test func discoveredSelectionsCompareEveryServiceAcrossIndependentKvVersionsAndNames() async throws {
        let readerA = VaultReader(transport: DiscoveryFixture(version: 2), validate: validatedFixture)
        let readerB = VaultReader(transport: DiscoveryFixture(version: 1), validate: validatedFixture)
        var a = discoverySettings(); a.mount = "FPMS-NT-V2"; a.environment = "uat-swim"
        var b = a; b.url = "https://other-uat.example.invalid/ui/"; b.environment = "qat-other"; b.token = "synthetic-token-B"
        let optionsA = try await readerA.discoverContents(a), optionsB = try await readerB.discoverContents(b)
        #expect(optionsA.directories(for: "uat-swim") == ["auth", "auth/nested", "payment", "promotion"])
        #expect(optionsB.directories(for: "qat-other") == ["auth", "auth/nested", "payment", "promotion"])
        let captureA = try await readerA.capture(readerA.preview(VaultTarget(a)))
        let captureB = try await readerB.capture(readerB.preview(VaultTarget(b)))
        #expect(captureA.entries.count == 4 && captureB.entries.count == 4)
        func map(_ entries: [[String: String]]) throws -> String {
            let request = try JSONSerialization.data(withJSONObject: ["op": "vaultSnapshot", "entries": entries])
            return try #require(CoreResponse.decode(CoreBridge.process(String(decoding: request, as: UTF8.self))).text)
        }
        let input = try JSONSerialization.data(withJSONObject: ["op": "compare", "kind": "json", "a": try map(captureA.entries), "b": try map(captureB.entries), "session": "discovered-batch"])
        let result = try CoreResponse.decode(CoreBridge.process(String(decoding: input, as: UTF8.self)))
        #expect(result.complete == true && result.summary?.total == 8 && result.summary?.typeChanged == 4 && result.summary?.same == 4)
        #expect(result.summary?.onlyA == 0 && result.summary?.onlyB == 0)
    }
}

extension VaultDiscoveryWorkspaceTests {
    @Test func explicitBrowserLinkSelectsOnlyHintsConfirmedByDiscovery() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: DiscoveryFixture(), validate: $0) })
        model.tool = .vault; model.vaultA = discoverySettings()
        model.vaultA.url = "https://uat.example.invalid/ui/vault/secrets/FPMS-NT-V2/kv/auth%2Fuat-swim"
        model.discoverVault(side: true); try await settle(model)
        #expect(model.vaultA.mount == "FPMS-NT-V2")
        model.vaultA.mount = "FPMS-NT-V2" // Keep exercising name discovery even on the old behavior.
        model.discoverVault(side: true, contents: true); try await settle(model)
        #expect(model.vaultA.environment == "uat-swim" && model.vaultA.directoryPattern == "**")
        model.cancel()
    }
}
extension VaultDiscoveryTests {
    @Test func productionBrowserLinksAreRejectedBeforeDiscovery() async throws {
        let transport = DiscoveryFixture(); let reader = VaultReader(transport: transport, validate: validatedFixture)
        var settings = discoverySettings()
        for path in ["prod/kv/auth%2Fconfig", "FPMS-NT-V2/kv/production%2Fconfig"] {
            settings.url = "https://uat.example.invalid/ui/vault/secrets/" + path
            await #expect(throws: VaultFailure.self) { try await reader.discoverConnection(settings) }
        }
        #expect(await transport.requests.isEmpty)
    }
    @Test func malformedKvVersionCannotDefaultToAReadableVersion() async throws {
        for options in [#"{"version":2}"#, #"{"version":true}"#, #""wrong-shape""#] {
            let transport = MatrixVault { _, _ in vaultResponse("{\"data\":{\"path\":\"FPMS-NT-V2/\",\"type\":\"kv\",\"options\":" + options + "}}") }
            let reader = VaultReader(transport: transport, validate: validatedFixture)
            var settings = discoverySettings(); settings.mount = "FPMS-NT-V2"
            await #expect(throws: VaultFailure.self) { try await reader.discoverContents(settings) }
            #expect(await transport.requests.count == 1)
        }
    }
}
