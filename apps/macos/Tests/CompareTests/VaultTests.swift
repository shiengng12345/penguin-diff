import Foundation
import Testing
import CoreBridge
import CompareShared
@testable import CompareUI

@Test func vaultBrowserLinkSeparatesMountAndLogicalPath() throws {
    let link = try VaultLink.parse("https://vault-fpms-aliyun-uat.platform99.me/ui/vault/secrets/FPMS-NT-V2/kv/auth%2Fuat-swim")
    #expect(link.origin == "https://vault-fpms-aliyun-uat.platform99.me")
    #expect(link.mount == "FPMS-NT-V2")
    #expect(link.path == "auth/uat-swim")
    #expect(link.version == 2)
}

actor FixtureVault: VaultTransport {
    var requests: [URLRequest] = []
    let denied: Bool
    let dynamicEngine: Bool
    init(denied: Bool = false, dynamicEngine: Bool = false) { self.denied = denied; self.dynamicEngine = dynamicEngine }
    func send(_ request: URLRequest) async throws -> VaultHTTPResponse {
        requests.append(request)
        let path = request.url!.path
        let body: String
        if path.contains("/sys/internal/ui/mounts/") {
            body = dynamicEngine ? #"{"data":{"path":"secret/","type":"database"}}"# : #"{"data":{"path":"secret/","type":"kv","options":{"version":"2"}}}"#
        } else if path == "/v1/secret/metadata/" || path == "/v1/secret/metadata" {
            body = #"{"data":{"keys":["auth/","common/","unrelated"]}}"#
        } else if path.hasPrefix("/v1/secret/metadata/") {
            body = #"{"data":{"keys":["uat-swim","qat-other","production"]}}"#
        } else if path.hasPrefix("/v1/secret/data/") {
            if denied { return .init(status:403, body:Data(#"{"errors":["do not echo secret/token"]}"#.utf8)) }
            body = request.url!.path.hasSuffix("uat-swim") ? #"{"data":{"data":{"PORT":3000,"big":9007199254740993}}}"# : #"{"data":{"data":{"PORT":"3000","big":9007199254740993}}}"#
        } else if path == "/v1/sys/namespaces" {
            let ns = request.value(forHTTPHeaderField:"X-Vault-Namespace") ?? ""
            body = ns == "sandbox/" ? #"{"data":{"keys":["team-a/","team-b/"]}}"# : #"{"data":{"keys":[]}}"#
        } else { throw VaultFailure.invalid("Unexpected route") }
        return .init(status:200,body:Data(body.utf8))
    }
}

func validatedFixture(_ raw: String, _ version: Int?, _ status: Int) async throws -> CoreResponse {
    var fields: [String:Any] = ["op":version == nil ? "validateJson" : "inspectVaultRead", "source":raw]
    if let version { fields["kvVersion"] = version; fields["httpStatus"] = status }
    let data = try JSONSerialization.data(withJSONObject:fields)
    return try CoreResponse.decode(CoreBridge.process(String(decoding:data,as:UTF8.self)))
}
func fixtureTarget(name: String = "uat-swim", namespace: String = "", pattern: String = ".") throws -> VaultTarget {
    var settings = VaultSettings()
    settings.url = "https://uat.example.invalid"; settings.token = "synthetic-token"; settings.mount = "secret"
    settings.namespace = namespace; settings.namespacePattern = pattern
    settings.environment = name; settings.confirmedNonProduction = true
    return try VaultTarget(settings)
}

@Test func vaultBatchUsesIndependentNamesAndReadsOnlyMatchedKvSecrets() async throws {
    let transport = FixtureVault()
    let reader = VaultReader(transport:transport, validate:validatedFixture)
    let first = try await reader.preview(fixtureTarget())
    #expect(Set(first.secrets.map(\.path)) == ["auth/uat-swim","common/uat-swim"])
    let a = try await reader.capture(first)
    let second = try await reader.preview(fixtureTarget(name:"qat-other"))
    let b = try await reader.capture(second)
    #expect(a.entries.map { $0["path"] } == b.entries.map { $0["path"] })
    func map(_ entries: [[String:String]]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject:["op":"vaultSnapshot","entries":entries])
        return try CoreResponse.decode(CoreBridge.process(String(decoding:data,as:UTF8.self))).text ?? ""
    }
    let request = try JSONSerialization.data(withJSONObject:["op":"compare","kind":"json","a":try map(a.entries),"b":try map(b.entries),"session":"live-fixture"])
    let result = try CoreResponse.decode(CoreBridge.process(String(decoding:request,as:UTF8.self)))
    #expect(result.summary?.typeChanged == 2)
    #expect(result.summary?.same == 2)
    let requests = await transport.requests
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField:"X-Vault-Token") == "synthetic-token" })
    #expect(!requests.contains { $0.url!.path.contains("/data/") && $0.url!.path.hasSuffix("production") })
    #expect(!requests.contains { $0.url!.path.contains("unrelated") })
}

@Test func vaultNamespaceWildcardUsesHeadersAndRelativePairing() async throws {
    let transport = FixtureVault()
    let reader = VaultReader(transport:transport, validate:validatedFixture)
    let plan = try await reader.preview(fixtureTarget(namespace:"sandbox",pattern:"team-*"))
    #expect(Set(plan.secrets.map(\.namespaceKey)) == ["team-a","team-b"])
    #expect(plan.secrets.count == 4)
    let requests = await transport.requests
    #expect(requests.filter { $0.url!.path == "/v1/sys/namespaces" }.count == 1)
    #expect(Set(requests.compactMap { $0.value(forHTTPHeaderField:"X-Vault-Namespace") }) == ["sandbox/","sandbox/team-a/","sandbox/team-b/"])
}

@Test func vaultDynamicEngineAndDeniedReadsNeverProduceMissingData() async throws {
    let dynamic = FixtureVault(dynamicEngine:true)
    let dynamicReader = VaultReader(transport:dynamic, validate:validatedFixture)
    await #expect(throws: VaultFailure.self) { try await dynamicReader.preview(fixtureTarget()) }
    #expect(await dynamic.requests.count == 1)
    let denied = FixtureVault(denied:true)
    let deniedReader = VaultReader(transport:denied, validate:validatedFixture)
    let plan = try await deniedReader.preview(fixtureTarget())
    await #expect(throws: VaultFailure.self) { try await deniedReader.capture(plan) }
    #expect(await denied.requests.filter { $0.url!.path.contains("/data/") }.count == 1)
}

@Test func vaultLiteralAndWildcardDirectoriesUseTheSameRelativePairKey() async throws {
    let reader = VaultReader(transport:FixtureVault(),validate:validatedFixture)
    var settings = VaultSettings(); settings.url = "https://uat.example.invalid"; settings.token = "synthetic-token"
    settings.mount = "secret"; settings.environment = "uat-swim"; settings.confirmedNonProduction = true; settings.directoryPattern = "auth"
    let literal = try await reader.preview(VaultTarget(settings))
    settings.directoryPattern = "**"
    let wildcard = try await reader.preview(VaultTarget(settings))
    #expect(literal.secrets.first?.directoryKey == wildcard.secrets.first(where:{ $0.path == "auth/uat-swim" })?.directoryKey)
}

@Test func vaultGlobDistinguishesSingleAndRecursiveSegments() throws {
    #expect(try VaultGlob("*/uat-swim").matches("auth/uat-swim"))
    #expect(try !VaultGlob("*/uat-swim").matches("team/auth/uat-swim"))
    #expect(try VaultGlob("**/uat-swim").matches("team/auth/uat-swim"))
    #expect(try !VaultGlob("**/uat-swim").matches("auth/prod"))
    #expect(try VaultGlob("team-?").matches("team-a"))
    #expect(throws: VaultFailure.self) { try VaultGlob("../*") }
}

@Test func vaultTargetAutomaticallyBlocksProductionLabelsAndUnsafeRoutes() throws {
    var settings = VaultSettings()
    settings.url = "https://uat.example.invalid"; settings.token = "synthetic-token"
    settings.mount = "secret"; settings.environment = "config"
    _ = try VaultTarget(settings)
    settings.url = "https://prod.example.invalid"
    #expect(throws: VaultFailure.self) { try VaultTarget(settings) }
    settings.url = "https://uat.example.invalid"; settings.mount = "../database"
    #expect(throws: VaultFailure.self) { try VaultTarget(settings) }
    settings.mount = "secret"; settings.token = "bad\r\nheader"
    #expect(throws: VaultFailure.self) { try VaultTarget(settings) }
}
