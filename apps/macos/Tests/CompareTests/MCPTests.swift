import Foundation
import Testing
import MCP
import CoreBridge
@testable import CompareUI

@MainActor final class DirectCoreWorker: WorkerSending {
    func send(_ request: String) async throws -> String { CoreBridge.process(request) }
    func abort() {}
}
private func resultText(_ result: CallTool.Result) -> String {
    result.content.compactMap { item in if case .text(let text,_,_) = item { return text }; return nil }.joined()
}

@Test @MainActor func mcpDefaultBatchRetainsIndependentCommonJSExports() async throws {
    let service = MCPService(workerFactory: { DirectCoreWorker() })
    for (a,b,path) in [
        ("module.exports={PORT:3000};","module.exports={PORT:4000};","$[\"module.exports\"].PORT"),
        ("exports.PORT=3000;","exports.PORT=4000;","$[\"module.exports\"].PORT"),
        ("var env={x:1};module.exports={extra:5};","var env={x:1};module.exports={};","$[\"module.exports\"].extra")
    ] {
        let result = await service.call(name:"env_compare",arguments:["a":.string(a),"b":.string(b)])
        #expect(result.isError != true)
        let json = try JSONSerialization.jsonObject(with:Data(resultText(result).utf8)) as! [String:Any]
        #expect((json["summary"] as? [String:Int])?["differences"] == 1 && json["complete"] as? Bool == true)
        let rows = try #require(json["rows"] as? [[String:Any]])
        #expect(rows.count == 1 && rows.first?["path"] as? String == path)
        #expect(json["includesValues"] as? Bool == false)
    }
    let paired = await service.call(name:"env_compare",arguments:["a":.string("var env={x:1};module.exports=env;"),"b":.string("var env={x:1};module.exports={x:1};")])
    let pairedJSON = try JSONSerialization.jsonObject(with:Data(resultText(paired).utf8)) as! [String:Any]
    #expect((pairedJSON["summary"] as? [String:Int])?["total"] == 2)
    #expect((pairedJSON["summary"] as? [String:Int])?["same"] == 2)
    #expect((pairedJSON["rows"] as? [Any])?.isEmpty == true)
}

@Test @MainActor func mcpDefaultsToWholeFileButSingleVariablesRemainExplicit() async throws {
    let service = MCPService(workerFactory: { DirectCoreWorker() })
    let input: [String:MCP.Value] = ["a":.string("var env={y:2,x:3};var happy={x:y};"), "b":.string("var env={y:2};var happy={};")]
    let batch = await service.call(name:"env_compare",arguments:input)
    let json = try JSONSerialization.jsonObject(with:Data(resultText(batch).utf8)) as! [String:Any]
    let summary = try #require(json["summary"] as? [String:Int])
    #expect(summary["total"] == 3 && summary["notComparable"] == 1)
    let rows = try #require(json["rows"] as? [[String:Any]])
    #expect(Set(rows.compactMap { $0["path"] as? String }) == ["$.env.x", "$.happy.x"])
    #expect(json["includesValues"] as? Bool == false)
    var single = input; single["rootA"] = .string("env"); single["rootB"] = .string("env")
    let picked = await service.call(name:"env_compare",arguments:single)
    let pickedJSON = try JSONSerialization.jsonObject(with:Data(resultText(picked).utf8)) as! [String:Any]
    #expect((pickedJSON["summary"] as? [String:Int])?["total"] == 2)
    #expect((pickedJSON["rows"] as? [[String:Any]])?.first?["path"] as? String == "$.x")
    single.removeValue(forKey:"rootB")
    #expect(await service.call(name:"env_compare",arguments:single).isError == true)
    let tool = try #require(MCPService.tools.first { $0.name == "env_compare" })
    #expect(tool.inputSchema.objectValue?["properties"]?.objectValue?["rootA"]?.objectValue?["default"]?.stringValue == "*")
}

@Test @MainActor func mcpWarningPagesRetainAllPositionsWithZeroRowsAndStrictOffsetValidation() async throws {
    let service = MCPService(workerFactory: { DirectCoreWorker() })
    let source = "var env={" + Array(repeating: "x:2", count: 402).joined(separator: ",") + "};"
    let initial = await service.call(name: "env_compare", arguments: ["a": .string(source), "b": .string("var env={x:2};")])
    let first = try JSONSerialization.jsonObject(with: Data(resultText(initial).utf8)) as! [String: Any]
    #expect(first["warningCount"] as? Int == 401)
    #expect((first["warnings"] as? [Any])?.count == 200)
    #expect(first["hasMoreWarnings"] as? Bool == true)
    let session = try #require(first["session"] as? String)
    var columns = ((first["warnings"] as? [[String: Any]]) ?? []).compactMap { $0["column"] as? Int }
    for (offset, count, more) in [(200, 200, true), (400, 1, false)] {
        let page = await service.call(name: "comparison_rows", arguments: ["session": .string(session), "warningOffset": .int(offset)])
        #expect(page.isError != true)
        let result = try JSONSerialization.jsonObject(with: Data(resultText(page).utf8)) as! [String: Any]
        let warnings = try #require(result["warnings"] as? [[String: Any]])
        #expect(warnings.count == count && result["warningCount"] as? Int == 401)
        #expect(result["hasMoreWarnings"] as? Bool == more)
        #expect((result["rows"] as? [Any])?.isEmpty == true)
        columns.append(contentsOf: warnings.compactMap { $0["column"] as? Int })
    }
    #expect(columns == Array(stride(from: 14, through: 1614, by: 4)))
    for offset in [MCP.Value.int(-1), .int(100001), .bool(true), .string("200")] {
        #expect(await service.call(name: "comparison_rows", arguments: ["session": .string(session), "warningOffset": offset]).isError == true)
    }
    let schema = try #require(MCPService.tools.first { $0.name == "comparison_rows" })
    #expect(schema.inputSchema.objectValue?["properties"]?.objectValue?["warningOffset"] != nil)
}

@Test @MainActor func mcpRetainsDuplicateWarningsWithNoMatchingRowsAndNoSourceSecrets() async throws {
    let service = MCPService(workerFactory: { DirectCoreWorker() })
    let response = await service.call(name: "env_compare", arguments: [
        "a": .string("var env={sensitive_key:'synthetic-secret',sensitive_key:2};"),
        "b": .string("var env={sensitive_key:2};")])
    let text = resultText(response)
    #expect(response.isError != true)
    #expect(!text.contains("synthetic-secret") && !text.contains("sensitive_key"))
    let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    #expect((json["rows"] as? [Any])?.isEmpty == true)
    let warnings = try #require(json["warnings"] as? [[String: Any]])
    #expect(warnings.count == 1 && warnings[0]["side"] as? String == "A")
    let page = await service.call(name: "comparison_rows", arguments: ["session": .string(json["session"] as! String)])
    let next = try JSONSerialization.jsonObject(with: Data(resultText(page).utf8)) as! [String: Any]
    #expect(try JSONSerialization.data(withJSONObject: warnings, options: .sortedKeys) == JSONSerialization.data(withJSONObject: next["warnings"]!, options: .sortedKeys))
}

@Test @MainActor func mcpComparesWithoutReturningValuesUnlessRequested() async throws {
    let service = MCPService(workerFactory:{ DirectCoreWorker() })
    let result = await service.call(name:"env_compare",arguments:["a":.string("var env={secret:'private-value',PORT:3000};"),"b":.string("var env={secret:'private-value',PORT:'3000'};")])
    #expect(result.isError != true)
    let text = resultText(result)
    #expect(!text.contains("private-value"))
    #expect(!text.contains("3000"))
    #expect(text.contains("TYPE_CHANGED"))
    let json = try JSONSerialization.jsonObject(with:Data(text.utf8)) as! [String:Any]
    let session = json["session"] as! String
    let page = await service.call(name:"comparison_rows",arguments:["session":.string(session),"includeValues":.bool(true)])
    #expect(resultText(page).contains("3000"))
}

@Test @MainActor func mcpValidatesParametersAndKeepsYamlOffline() async {
    let service = MCPService(workerFactory:{ DirectCoreWorker() },authorization:{ throw VaultFailure.invalid("synthetic unauthorized fixture") })
    let yaml = await service.call(name:"yaml_format",arguments:["source":.string("x:  1\n")])
    #expect(resultText(yaml) == "x: 1\n")
    #expect(await service.call(name:"yaml_format",arguments:["source":.string("x: 1"),"indent":.bool(true)]).isError == true)
    #expect(await service.call(name:"vault_preview",arguments:["url":.string("https://prod.example.invalid")]).isError == true)
    #expect(await service.call(name:"vault_preview",arguments:[:]).isError == true)
}

@MainActor private final class AuthorizationFixture {
    var enabled = true
    let pair: MCPVaultPair
    init() {
        var a = VaultSettings(); a.url = "https://uat.example.invalid"; a.token = "synthetic-token"; a.mount = "secret"; a.environment = "uat-swim"; a.confirmedNonProduction = true
        var b = a; b.environment = "qat-other"
        let allowedA = ["auth","common"].map { VaultSecret(namespace:"",namespaceKey:".",path:$0 + "/uat-swim",directoryKey:$0,kvVersion:2) }
        let allowedB = ["auth","common"].map { VaultSecret(namespace:"",namespaceKey:".",path:$0 + "/qat-other",directoryKey:$0,kvVersion:2) }
        pair = .init(a:a,b:b,authorizedAt:Date(),allowedA:allowedA,allowedB:allowedB)
    }
    func load() throws -> MCPVaultPair { guard enabled else { throw VaultFailure.invalid("revoked") }; return pair }
}

@Test @MainActor func mcpRejectsAChangedWildcardInventoryBeforeReadingValues() async throws {
    let store = AuthorizationFixture(), transport = FixtureVault()
    let narrowed = MCPVaultPair(a:store.pair.a,b:store.pair.b,authorizedAt:Date(),allowedA:Array(store.pair.allowedA.prefix(1)),allowedB:store.pair.allowedB)
    let service = MCPService(workerFactory:{ DirectCoreWorker() },vaultFactory:{ VaultReader(transport:transport,validate:$0) },authorization:{ narrowed })
    let result = await service.call(name:"vault_preview",arguments:[:])
    #expect(result.isError == true)
    #expect(resultText(result).contains("MCP_SCOPE_CHANGED"))
    #expect(await transport.requests.allSatisfy { !$0.url!.path.contains("/data/") })
}

@Test @MainActor func broadeningNamespacePatternRequiresFreshNonProductionConfirmation() {
    let model = Workspace(clientFactory:{ DirectCoreWorker() })
    var old = VaultSettings(); old.confirmedNonProduction = true
    var updated = old; updated.namespacePattern = "**"
    model.vaultA = updated
    model.vaultChanged(side:true,old:old,new:updated)
    #expect(!model.vaultA.confirmedNonProduction)
}

@Test @MainActor func mcpVaultUsesAuthorizedScopeAndRevocationBlocksCachedResults() async throws {
    let store = AuthorizationFixture()
    let transport = FixtureVault()
    let service = MCPService(workerFactory:{ DirectCoreWorker() },vaultFactory:{ VaultReader(transport:transport,validate:$0) },authorization:{ try store.load() })
    let preview = await service.call(name:"vault_preview",arguments:[:])
    #expect(preview.isError != true)
    let plan = try JSONSerialization.jsonObject(with:Data(resultText(preview).utf8)) as! [String:Any]
    let comparison = await service.call(name:"vault_compare",arguments:["planId":.string(plan["planId"] as! String)])
    #expect(comparison.isError != true)
    #expect(!resultText(comparison).contains("synthetic-token"))
    #expect(!resultText(comparison).contains("9007199254740993"))
    let report = try JSONSerialization.jsonObject(with:Data(resultText(comparison).utf8)) as! [String:Any]
    store.enabled = false
    let denied = await service.call(name:"comparison_rows",arguments:["session":.string(report["session"] as! String),"includeValues":.bool(true)])
    #expect(denied.isError == true)
    #expect(!resultText(denied).contains("3000"))
}
