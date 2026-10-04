import Foundation
import Testing
import CoreBridge
import CompareShared
@testable import CompareUI

actor MatrixVault: VaultTransport {
    typealias Handler = @Sendable (URLRequest, Int) throws -> VaultHTTPResponse
    private let handler: Handler
    private(set) var requests: [URLRequest] = []
    init(_ handler: @escaping Handler) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> VaultHTTPResponse {
        requests.append(request)
        return try handler(request, requests.count)
    }
}

/// A cooperative test transport that can deliberately hold one value read
/// past a caller's cancellation. Releasing it later exercises the reader's
/// post-response cancellation check instead of manufacturing a transport
/// error.
actor GatedVault: VaultTransport {
    private(set) var requests: [URLRequest] = []
    private var holdNextData = true
    private var held: CheckedContinuation<VaultHTTPResponse, any Error>?

    func send(_ request: URLRequest) async throws -> VaultHTTPResponse {
        requests.append(request)
        let path = request.url!.path
        if path.contains("/sys/internal/ui/mounts/") { return mountResponse() }
        if path == "/v1/secret/metadata" || path == "/v1/secret/metadata/" {
            return vaultResponse(#"{"data":{"keys":["auth/","common/"]}}"#)
        }
        if path == "/v1/secret/metadata/auth" || path == "/v1/secret/metadata/auth/" || path == "/v1/secret/metadata/common" || path == "/v1/secret/metadata/common/" {
            return vaultResponse(#"{"data":{"keys":["uat-swim","qat-other"]}}"#)
        }
        if path.contains("/data/") && holdNextData {
            holdNextData = false
            return try await withCheckedThrowingContinuation { continuation in
                held = continuation
            }
        }
        return vaultResponse(#"{"data":{"data":{"PORT":3000},"metadata":{"version":7}}}"#)
    }

    func isHoldingData() -> Bool { held != nil }

    func releaseHeldData() {
        let continuation = held
        held = nil
        continuation?.resume(returning: vaultResponse(#"{"data":{"data":{"PORT":3000},"metadata":{"version":7}}}"#))
    }
}
func vaultResponse(_ text: String, status: Int = 200) -> VaultHTTPResponse {
    .init(status:status,body:Data(text.utf8))
}
func mountResponse(version: Int = 2) -> VaultHTTPResponse {
    vaultResponse("{\"data\":{\"path\":\"secret/\",\"type\":\"kv\",\"options\":{\"version\":\"\(version)\"}}}")
}
func literalTarget() throws -> VaultTarget {
    var settings=VaultSettings(); settings.url="https://uat.example.invalid"; settings.token="synthetic-token"
    settings.mount="secret"; settings.environment="config"; settings.directoryPattern="."; settings.confirmedNonProduction=true
    return try VaultTarget(settings)
}
func requireVaultCode(_ code: String, _ operation: () async throws -> Void) async throws {
    do { try await operation(); Issue.record("Expected failure: \(code)") }
    catch let error as VaultFailure { #expect(error.code == code) }
}

@Test func vaultV1V2SingleSecretWithoutListPermissionsAndDistinctRoutes() async throws {
    for version in [1,2] {
        let transport=MatrixVault { request,_ in
            if request.url!.path.contains("/sys/internal/ui/mounts/") {return mountResponse(version:version)}
            #expect(request.url!.query == nil)
            #expect(request.url!.path == (version == 2 ? "/v1/secret/data/config" : "/v1/secret/config"))
            return vaultResponse(version == 2 ? #"{"data":{"data":{"n":9007199254740993},"metadata":{"version":7}}}"# : #"{"data":{"n":9007199254740993}}"#)
        }
        let reader=VaultReader(transport:transport,validate:validatedFixture)
        let plan=try await reader.preview(literalTarget())
        #expect(plan.secrets.count == 1)
        let captured=try await reader.capture(plan)
        #expect(captured.entries.first?["format"] == "plain-object")
        #expect(captured.observations.first?.metadata.kvVersion == version)
        #expect(captured.entries.first?["response"]?.contains("9007199254740993") == true)
        #expect(await transport.requests.count == 3)
        #expect(await transport.requests.allSatisfy { $0.httpMethod == "GET" && $0.url!.query == nil })
    }
}

@Test func vaultStatusAndAmbiguous404MatrixNeverClaimsMissing() async throws {
    for status in [301,302,307,308,401,403,404,429,500,503] {
        let transport=MatrixVault { _,_ in vaultResponse(#"{"errors":["synthetic-secret-do-not-echo"]}"#,status:status) }
        let reader=VaultReader(transport:transport,validate:validatedFixture)
        let code=(300...399).contains(status) ? "VAULT_REDIRECT_BLOCKED" : "VAULT_HTTP_\(status)"
        do { _=try await reader.preview(literalTarget()); Issue.record("Unexpected success") }
        catch let error as VaultFailure {
            #expect(error.code == code)
            #expect(!error.localizedDescription.contains("synthetic-secret-do-not-echo"))
        }
        #expect(await transport.requests.count == 1)
    }
    for body in [#"{"errors":["denied"]}"#,#"{"errors":[],"other":1}"#,#"{"data":null}"#] {
        let transport=MatrixVault { _,count in count == 1 ? mountResponse() : vaultResponse(body,status:404) }
        let reader=VaultReader(transport:transport,validate:validatedFixture)
        try await requireVaultCode("VAULT_HTTP_404") { _=try await reader.preview(fixtureTarget()) }
    }
    let transport=MatrixVault { _,count in count == 1 ? mountResponse() : vaultResponse(#"{"errors":[]}"#,status:404) }
    let reader=VaultReader(transport:transport,validate:validatedFixture)
    try await requireVaultCode("VAULT_NO_MATCH") { _=try await reader.preview(fixtureTarget()) }
    #expect(await transport.requests.count == 2)
}

@Test func vaultCaptureCancellationDiscardsPartialEntriesAndRetryStartsFresh() async throws {
    let transport = GatedVault()
    let reader = VaultReader(transport: transport, validate: validatedFixture)
    let target = try literalTarget()
    let secrets = ["first", "second"].map {
        VaultSecret(namespace: "", namespaceKey: ".", path: $0 + "/config", directoryKey: $0, kvVersion: 2)
    }
    let plan = VaultPlan(target: target, secrets: secrets, discoveredNamespaces: [""], created: Date())
    let task = Task { try await reader.capture(plan) }
    let holdDeadline = ContinuousClock.now + .seconds(3)
    while !(await transport.isHoldingData()), ContinuousClock.now < holdDeadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    guard await transport.isHoldingData() else {
        task.cancel()
        await transport.releaseHeldData()
        _ = try? await task.value
        Issue.record("Vault capture did not reach its gated data request")
        return
    }
    task.cancel()
    await transport.releaseHeldData()
    do {
        _ = try await task.value
        Issue.record("Cancelled Vault capture unexpectedly returned a partial result")
    } catch {
        #expect(error is CancellationError)
    }
    #expect(await transport.requests.count == 2)

    let retry = try await reader.capture(plan)
    #expect(retry.entries.count == 2 && retry.observations.count == 2)
    #expect(retry.entries.map { $0["path"] } == ["first", "second"])
    #expect(await transport.requests.count == 5)
}

@Test @MainActor func vaultLateResponseAfterScopeChangeCannotRestoreStaleWorkspace() async throws {
    let transport = GatedVault()
    let model = Workspace(
        clientFactory: { DirectCoreWorker() },
        vaultFactory: { VaultReader(transport: transport, validate: $0) }
    )
    model.tool = .vault
    model.switchTool()
    var a = VaultSettings()
    a.url = "https://uat.example.invalid"
    a.mount = "secret"
    a.token = "synthetic-token"
    a.environment = "uat-swim"
    a.confirmedNonProduction = true
    model.vaultA = a
    var b = a
    b.environment = "qat-other"
    model.vaultB = b

    model.previewVault()
    while model.busy { try await Task.sleep(for: .milliseconds(1)) }
    #expect(model.vaultPlanA != nil && model.vaultPlanB != nil)
    model.run()
    let holdDeadline = ContinuousClock.now + .seconds(3)
    while !(await transport.isHoldingData()), ContinuousClock.now < holdDeadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    guard await transport.isHoldingData() else {
        model.cancel()
        Issue.record("Workspace Vault compare did not reach its gated data request")
        return
    }

    let old = model.vaultA
    model.vaultA.environment = "new-name"
    model.vaultChanged(side: true, old: old, new: model.vaultA)
    #expect(!model.busy && model.vaultPlanA == nil && model.vaultPlanB == nil)

    // This response arrives after the user changed the scope. It must be
    // consumed by the cancelled reader but cannot restore the old result.
    await transport.releaseHeldData()
    try await Task.sleep(for: .milliseconds(20))
    #expect(model.summary == nil && model.rows.isEmpty && model.vaultCaptureInfo.isEmpty)
    #expect(!model.error && model.vaultSources.isEmpty)
    model.cancel()
}

@Test func vaultUntrustedControlResponsesFailClosedBeforeReadingSecrets() async throws {
    let invalidBodies=[
        #"{"data":{"keys":["../escape/"]}}"#,
        #"{"data":{"keys":["a/b/"]}}"#,
        #"{"data":{"keys":["%2e%2e/"]}}"#,
        #"{"data":{"keys":["config","config"]}}"#,
        #"{"data":{"keys":"config"}}"#,
        #"{"data":null}"#,
        #"{"data":{"keys":["config"]},"data":{"keys":[]}}"#,
        "{",
    ]
    for body in invalidBodies {
        let transport=MatrixVault { _,count in count == 1 ? mountResponse() : vaultResponse(body) }
        let reader=VaultReader(transport:transport,validate:validatedFixture)
        await #expect(throws:(any Error).self) { try await reader.preview(fixtureTarget()) }
        #expect(await transport.requests.count == 2)
        #expect(await transport.requests.allSatisfy { !$0.url!.path.contains("/data/") })
    }
    let malformed=MatrixVault { _,_ in .init(status:200,body:Data([0xff,0xfe])) }
    let reader=VaultReader(transport:malformed,validate:validatedFixture)
    try await requireVaultCode("VAULT_RESPONSE_INVALID") { _=try await reader.preview(literalTarget()) }
}

@Test func vaultMountMismatchChangedVersionAndExpiredPlanDoNotReadValues() async throws {
    for body in [#"{"data":{"path":"other/","type":"kv"}}"#,#"{"data":{"path":"secret/","type":"kv","options":{"version":"3"}}}"#,#"{"data":{"path":"secret/","type":"database"}}"#] {
        let transport=MatrixVault { _,_ in vaultResponse(body) }
        let reader=VaultReader(transport:transport,validate:validatedFixture)
        try await requireVaultCode("VAULT_MOUNT_UNCONFIRMED") { _=try await reader.preview(literalTarget()) }
    }
    let transport=MatrixVault { _,count in mountResponse(version:count == 1 ? 2 : 1) }
    let reader=VaultReader(transport:transport,validate:validatedFixture)
    let plan=try await reader.preview(literalTarget())
    try await requireVaultCode("VAULT_SOURCE_CHANGED") { _=try await reader.capture(plan) }
    #expect(await transport.requests.count == 2)
    let expired=VaultPlan(target:plan.target,secrets:plan.secrets,discoveredNamespaces:plan.discoveredNamespaces,created:Date().addingTimeInterval(-301))
    try await requireVaultCode("VAULT_PLAN_EXPIRED") { _=try await reader.capture(expired) }
    #expect(await transport.requests.count == 2)
}

@Test func vaultRecursiveDirectoryNamespaceAndResponseBudgetsAreBounded() async throws {
    let deep=MatrixVault { request,_ in
        request.url!.path.contains("/sys/internal/ui/mounts/") ? mountResponse() : vaultResponse(#"{"data":{"keys":["child/","uat-swim"]}}"#)
    }
    let reader=VaultReader(transport:deep,validate:validatedFixture)
    try await requireVaultCode("RESOURCE_LIMIT") { _=try await reader.preview(fixtureTarget()) }
    #expect(await deep.requests.count == 18)
    let wide=MatrixVault { request,_ in
        if request.url!.path.contains("/sys/internal/ui/mounts/") {return mountResponse()}
        let keys=(0..<1001).map { "d\($0)/" }
        return .init(status:200,body:try JSONSerialization.data(withJSONObject:["data":["keys":keys]]))
    }
    let wideReader=VaultReader(transport:wide,validate:validatedFixture)
    try await requireVaultCode("RESOURCE_LIMIT") { _=try await wideReader.preview(fixtureTarget()) }
    #expect(await wide.requests.count == 2)
    let namespaces=MatrixVault { _,_ in
        .init(status:200,body:try JSONSerialization.data(withJSONObject:["data":["keys":(0..<101).map {"team-\($0)/"}]]))
    }
    let nsReader=VaultReader(transport:namespaces,validate:validatedFixture)
    try await requireVaultCode("RESOURCE_LIMIT") { _=try await nsReader.preview(fixtureTarget(namespace:"sandbox",pattern:"*")) }
    #expect(await namespaces.requests.count == 1)
    let oversized=MatrixVault { _,_ in .init(status:200,body:Data(repeating:32,count:20*1024*1024+1)) }
    let largeReader=VaultReader(transport:oversized,validate:validatedFixture)
    try await requireVaultCode("RESOURCE_LIMIT") { _=try await largeReader.preview(literalTarget()) }
}

@Test func vaultCaptureStopsAt500RequestsWithoutPartialSuccess() async throws {
    let transport=MatrixVault { request,_ in
        request.url!.path.contains("/sys/internal/ui/mounts/") ? mountResponse() : vaultResponse(#"{"data":{"data":{"x":1}}}"#)
    }
    let target=try literalTarget()
    let plan=VaultPlan(target:target,secrets:(0..<500).map { .init(namespace:"",namespaceKey:".",path:"d\($0)/config",directoryKey:"d\($0)",kvVersion:2) },discoveredNamespaces:[""],created:Date())
    let reader=VaultReader(transport:transport,validate:validatedFixture)
    try await requireVaultCode("RESOURCE_LIMIT") { _=try await reader.capture(plan) }
    #expect(await transport.requests.count == 500)
}

@Test func vaultLeafAndSameNamedDirectoryStayDistinct() async throws {
    let transport=MatrixVault { request,_ in
        if request.url!.path.contains("/sys/internal/ui/mounts/") {return mountResponse()}
        if request.url!.path == "/v1/secret/metadata" {return vaultResponse(#"{"data":{"keys":["uat-swim","uat-swim/"]}}"#)}
        return vaultResponse(#"{"data":{"keys":["uat-swim"]}}"#)
    }
    let reader=VaultReader(transport:transport,validate:validatedFixture)
    let plan=try await reader.preview(fixtureTarget())
    #expect(Set(plan.secrets.map(\.path)) == ["uat-swim","uat-swim/uat-swim"])
    #expect(Set(plan.secrets.map(\.directoryKey)) == [".","uat-swim"])
}

@Test func vaultDiscoveredProductionNamespaceStopsAtDiscovery() async throws {
    let transport=MatrixVault { _,_ in vaultResponse(#"{"data":{"keys":["prod/"]}}"#) }
    let reader=VaultReader(transport:transport,validate:validatedFixture)
    try await requireVaultCode("VAULT_SCOPE_INVALID") { _=try await reader.preview(fixtureTarget(namespace:"sandbox",pattern:"**")) }
    #expect(await transport.requests.count == 1)
}

// A later failure must discard earlier successful reads and never request the
// remaining secret. A retry uses a fresh batch, even with the same reader/plan.
@Test func vaultLaterSecretFailureStopsBatchAndRetryStartsFresh() async throws {
    for version in [1, 2] {
        for status in [403, 404, 429, 503] {
            let transport = MatrixVault { request, count in
                if request.url!.path.contains("/sys/internal/ui/mounts/") { return mountResponse(version: version) }
                if count == 3 { return vaultResponse(#"{"errors":["synthetic-private-do-not-display"]}"#, status: status) }
                return vaultResponse(version == 2
                    ? #"{"data":{"data":{"n":9007199254740993},"metadata":{"version":7}}}"#
                    : #"{"data":{"n":9007199254740993}}"#)
            }
            let reader = VaultReader(transport: transport, validate: validatedFixture)
            let target = try literalTarget()
            let secrets = ["first", "second", "third"].map {
                VaultSecret(namespace: "", namespaceKey: ".", path: $0 + "/config", directoryKey: $0, kvVersion: version)
            }
            let plan = VaultPlan(target: target, secrets: secrets, discoveredNamespaces: [""], created: Date())
            do { _ = try await reader.capture(plan); Issue.record("Expected entire-batch failure") }
            catch let failure as VaultFailure {
                #expect(failure.code == "VAULT_HTTP_\(status)")
                #expect(!failure.message.contains("synthetic-private"))
            }
            let failedRequests = await transport.requests
            #expect(failedRequests.count == 3)
            #expect(failedRequests.last?.url?.path.hasSuffix("/second/config") == true)
            #expect(!failedRequests.contains { $0.url!.path.hasSuffix("/third/config") })
            let retry = try await reader.capture(plan)
            #expect(retry.entries.count == 3 && retry.observations.count == 3)
            #expect(retry.entries.map { $0["path"] } == ["first", "second", "third"])
            #expect(retry.entries.allSatisfy { $0["response"]?.contains("9007199254740993") == true })
            let allRequests = await transport.requests
            #expect(allRequests.count == 7)
            #expect(allRequests[3].url!.path.contains("/sys/internal/ui/mounts/"))
            #expect(allRequests.allSatisfy { $0.httpMethod == "GET" && $0.url!.query == nil })
        }
    }
}

// The root and first child succeed before a later child denies LIST. An earlier
// matched secret must not escape as a partial plan or trigger secret reads.
@Test func vaultLaterChildListFailureDiscardsPartialPlanAndRetryEnumeratesAgain() async throws {
    for version in [1, 2] {
        let transport = MatrixVault { request, count in
            if request.url!.path.contains("/sys/internal/ui/mounts/") { return mountResponse(version: version) }
            #expect(request.url!.query == "list=true")
            if count == 4 { return vaultResponse(#"{"errors":["synthetic-private-do-not-display"]}"#, status: 403) }
            let rootPath = version == 2 ? "/v1/secret/metadata" : "/v1/secret"
            return vaultResponse(request.url!.path == rootPath
                ? #"{"data":{"keys":["first/","second/","third/"]}}"#
                : #"{"data":{"keys":["uat-swim"]}}"#)
        }
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        do { _ = try await reader.preview(fixtureTarget()); Issue.record("Expected entire-preview failure") }
        catch let failure as VaultFailure {
            #expect(failure.code == "VAULT_HTTP_403" && !failure.message.contains("synthetic-private"))
        }
        let failedRequests = await transport.requests
        #expect(failedRequests.count == 4)
        #expect(failedRequests.last?.url?.path.hasSuffix("/second") == true)
        #expect(!failedRequests.contains { $0.url!.path.hasSuffix("/third") })
        let retry = try await reader.preview(fixtureTarget())
        #expect(retry.secrets.map(\.path) == ["first/uat-swim", "second/uat-swim", "third/uat-swim"])
        let allRequests = await transport.requests
        #expect(allRequests.count == 9)
        #expect(allRequests[4].url!.path.contains("/sys/internal/ui/mounts/"))
        #expect(allRequests.allSatisfy { $0.httpMethod == "GET" && !$0.url!.path.contains("/data/") })
    }
}
