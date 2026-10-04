import Foundation
import Testing
import CoreBridge
import CompareShared
@testable import CompareUI

@MainActor private func settled(_ model: Workspace, _ predicate: () -> Bool) async throws {
    let deadline=ContinuousClock.now + .seconds(3)
    while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for:.milliseconds(1)) }
    try #require(predicate(), "Workspace did not settle: \(model.notice)")
}

@Suite(.serialized)
struct WorkspaceQuality {
    @Test @MainActor func defaultBatchRetainsIndependentCommonJSExports() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        for (a,b,name) in [
            ("module.exports={PORT:3000};","module.exports={PORT:4000};","[\"module.exports\"].PORT"),
            ("exports.PORT=3000;","exports.PORT=4000;","[\"module.exports\"].PORT"),
            ("var env={x:1};module.exports={extra:5};","var env={x:1};module.exports={};","[\"module.exports\"].extra")
        ] {
            model.a=a; model.b=b; model.changed(); model.run()
            try await settled(model) { !model.busy && model.summary != nil }
            #expect(model.summary?.differences == 1 && model.complete)
            #expect(model.rows.count == 1 && model.resultName(model.rows[0].path) == name)
        }
        model.a="var env={x:1};module.exports=env;"
        model.b="var env={x:1};module.exports={x:1};"
        model.changed(); model.run()
        try await settled(model) { !model.busy && model.summary != nil }
        #expect(model.summary?.total == 2 && model.summary?.same == 2 && model.rows.isEmpty && model.complete)
        model.cancel()
    }
    @Test @MainActor func rootRefreshNeverSilentlyReplacesAMissingSelectedVariable() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.a="var alpha={x:1};"; model.b=model.a
        model.rootA="alpha"; model.rootB="alpha"
        model.a="var beta={x:2};"; model.changed(side:true); model.inspectRoots()
        try await settled(model) { !model.busy && model.rootsA.contains("beta") }
        #expect(model.rootA == "alpha" && model.rootB == "alpha")
        model.run(); try await settled(model) { !model.busy }
        #expect(model.error && model.summary == nil && model.notice.contains("ROOT_NOT_FOUND"))
        model.cancel()
    }
    @Test @MainActor func defaultBatchComparesEveryVariableAndCanSelectOne() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        #expect(model.rootA == "*" && model.rootB == "*")
        #expect(model.resultName("$") == "全部变量")
        model.preferences.language = .english
        #expect(model.resultName("$") == "All variables")
        model.preferences.language = .simplifiedChinese
        model.a = "var env={y:2,x:3};var happy={x:y};"
        model.b = "var env={y:2};var happy={};"
        model.run()
        // Comparison completion precedes its separate filtered-rows request.
        // Wait for that request too; the initial comparison page includes SAME.
        try await settled(model) { !model.busy && model.summary?.total == 3 && model.matched == 2 }
        #expect(model.summary?.same == 1 && model.summary?.onlyA == 1 && model.summary?.notComparable == 1)
        #expect(!model.complete && Set(model.rows.map { model.resultName($0.path) }) == ["env.x", "happy.x"])
        #expect(model.rows.first { $0.path == "$.happy.x" }?.status == "NOT_COMPARABLE")
        model.filter = "all"; model.loadRows(reset: true)
        try await settled(model) { model.matched == 3 }
        #expect(Set(model.rows.map { model.resultName($0.path) }) == ["env.x", "env.y", "happy.x"])
        model.a = "var env={y:2,x:3};var happy={x:env.y};"
        model.changed(side: true); model.run()
        try await settled(model) { !model.busy && model.summary?.total == 3 }
        #expect(model.complete && model.summary?.onlyA == 2 && model.summary?.notComparable == 0)
        model.inspectRoots()
        try await settled(model) { !model.busy && model.rootsA.contains("happy") }
        #expect(model.rootA == "*" && model.rootB == "*")
        model.rootA = "env"; model.rootB = "env"; model.changed(); model.run()
        try await settled(model) { !model.busy && model.summary?.total == 2 }
        model.filter = "all"; model.loadRows(reset: true)
        try await settled(model) { model.matched == 2 }
        #expect(Set(model.rows.map { model.resultName($0.path) }) == ["x", "y"])
        model.cancel()
    }

    @Test @MainActor func missingNullUndefinedAndEmptyValuesRemainDistinctInRowsAndDetails() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.a = "var env={nullValue:null,emptyValue:'',undefinedValue:undefined,undefinedOnly:undefined,onlyA:1};"
        model.b = "var env={nullValue:null,emptyValue:'',undefinedValue:undefined,onlyB:2};"
        model.run()
        try await settled(model) { !model.busy && model.summary?.total == 6 && model.matched == 3 }
        #expect(model.summary?.same == 3 && model.summary?.onlyA == 2 && model.summary?.onlyB == 1)
        #expect(model.complete)
        model.filter = "all"
        model.loadRows(reset: true)
        try await settled(model) { !model.busy && model.matched == 6 }
        let byName = Dictionary(uniqueKeysWithValues: model.rows.map { (model.resultName($0.path), $0) })
        let nullRow = try #require(byName["env.nullValue"])
        let emptyRow = try #require(byName["env.emptyValue"])
        let undefinedRow = try #require(byName["env.undefinedValue"])
        let undefinedOnlyRow = try #require(byName["env.undefinedOnly"])
        let onlyARow = try #require(byName["env.onlyA"])
        let onlyBRow = try #require(byName["env.onlyB"])
        #expect(nullRow.a.type == "Null" && nullRow.b.type == "Null" && nullRow.a.display == "null")
        #expect(emptyRow.a.type == "String" && emptyRow.a.display == "\"\"" && emptyRow.a.present)
        #expect(undefinedRow.a.type == "Undefined" && undefinedRow.b.type == "Undefined" && undefinedRow.a.display == "undefined")
        #expect(undefinedOnlyRow.a.type == "Undefined" && undefinedOnlyRow.a.present && undefinedOnlyRow.b.type == "Missing" && !undefinedOnlyRow.b.present)
        #expect(onlyARow.a.present && onlyARow.b.type == "Missing" && !onlyARow.b.present)
        #expect(onlyBRow.a.type == "Missing" && onlyBRow.b.present)
        model.selected = nullRow.id
        model.inspectSelection()
        try await settled(model) { model.detail != nil }
        #expect(model.detail?.a.type == "Null" && model.detail?.b.type == "Null")
        #expect(model.detail?.a.display == "null" && model.detail?.b.display == "null")
        for name in ["env.emptyValue", "env.undefinedValue", "env.undefinedOnly", "env.onlyA", "env.onlyB"] {
            let selected = try #require(byName[name])
            model.selected = selected.id
            model.inspectSelection()
            try await settled(model) { model.detail?.id == selected.id }
            #expect(model.detail?.id == selected.id)
            if name == "env.undefinedOnly" || name == "env.onlyA" {
                #expect(model.detail?.a.present == true && model.detail?.a.type != "Missing")
                #expect(model.detail?.b.present == false && model.detail?.b.type == "Missing")
            } else if name == "env.onlyB" {
                #expect(model.detail?.a.present == false && model.detail?.a.type == "Missing")
                #expect(model.detail?.b.present == true && model.detail?.b.type != "Missing")
            } else {
                #expect(model.detail?.a.present == true && model.detail?.b.present == true)
                if name == "env.emptyValue" {
                    #expect(model.detail?.a.type == "String" && model.detail?.b.type == "String")
                    #expect(model.detail?.a.display == "\"\"" && model.detail?.b.display == "\"\"")
                } else {
                    #expect(model.detail?.a.type == "Undefined" && model.detail?.b.type == "Undefined")
                    #expect(model.detail?.a.display == "undefined" && model.detail?.b.display == "undefined")
                }
            }
        }

        model.a = "var env={nullValue:null,emptyValue:'',undefinedValue:undefined};"
        model.b = "var env={nullValue:undefined,emptyValue:null,undefinedValue:''};"
        model.changed(); model.run()
        try await settled(model) { !model.busy && model.summary?.total == 3 && model.matched == 3 }
        #expect(model.summary?.typeChanged == 3 && model.summary?.differences == 3)
        for row in model.rows {
            switch row.path {
            case "$.env.emptyValue":
                #expect(row.status == "TYPE_CHANGED" && row.a.type == "String" && row.b.type == "Null")
            case "$.env.nullValue":
                #expect(row.status == "TYPE_CHANGED" && row.a.type == "Null" && row.b.type == "Undefined")
            case "$.env.undefinedValue":
                #expect(row.status == "TYPE_CHANGED" && row.a.type == "Undefined" && row.b.type == "String")
            default:
                Issue.record("Unexpected cross-type row: \(row.path)")
            }
            model.selected = row.id
            model.inspectSelection()
            try await settled(model) { model.detail?.id == row.id }
            #expect(model.detail?.a.present == true && model.detail?.b.present == true)
            #expect(model.detail?.a.type == row.a.type && model.detail?.b.type == row.b.type)
        }
        model.cancel()
    }
    @Test @MainActor func warningPreviewCountAndBudgetFailureDoNotLeaveAFalseResult() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.a = "var env={" + Array(repeating: "x:2", count: 402).joined(separator: ",") + "};"
        model.b = "var env={x:2};"; model.run()
        try await settled(model) { !model.busy && model.summary != nil }
        #expect(model.warningCount == 401 && model.warnings.count == 200)
        #expect(model.summary?.same == 1 && model.matched == 0)
        model.showSettings(); model.closeSettings()
        #expect(model.warningCount == 401)
        model.a = "var env={" + Array(repeating: "x:2", count: 100002).joined(separator: ",") + "};"
        model.changed(); model.run()
        try await settled(model) { !model.busy && model.error }
        #expect(model.summary == nil && model.warnings.isEmpty && model.warningCount == 0)
        #expect(model.notice.contains("RESOURCE_LIMIT"))
        model.a = model.b; model.changed(); model.run()
        try await settled(model) { !model.busy && model.summary != nil }
        #expect(!model.error && model.warningCount == 0 && model.summary?.same == 1)
        model.cancel()
    }
    @Test @MainActor func sourceWarningsSurviveSettingsAndFiltersThenClearOnNewRuns() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.a = "var env={private_key:'synthetic-secret',private_key:2};"
        model.b = "var env={private_key:2};"
        model.run()
        try await settled(model) { !model.busy && model.summary != nil }
        #expect(model.complete && model.summary?.same == 1 && model.matched == 0)
        let warning = try #require(model.warnings.first)
        #expect(model.warnings.count == 1 && warning.side == "A")
        #expect(warning.code == "JS_DUPLICATE_PROPERTY" && warning.line == 1)
        #expect(warning.previousLine == 1 && warning.previousColumn < warning.column)
        model.showSettings(); model.closeSettings()
        #expect(model.warnings.count == 1)
        model.filter = "all"; model.loadRows(reset: true)
        try await settled(model) { model.matched == 1 }
        #expect(model.warnings.count == 1)
        model.a = "var env={"; model.changed(); model.run()
        #expect(model.warnings.isEmpty)
        try await settled(model) { !model.busy && model.error }
        #expect(model.warnings.isEmpty)
        model.a = "var env={x:1,x:2};"; model.b = "var env={x:2};"; model.changed(); model.run()
        try await settled(model) { !model.busy && model.warnings.count == 1 }
        model.tool = .vault; model.switchTool()
        #expect(model.warnings.isEmpty)
        model.vaultLive = false; model.a = "{}"; model.b = "{}"; model.run()
        try await settled(model) { !model.busy && model.summary != nil }
        #expect(model.warnings.isEmpty)
        model.cancel()
    }
    @Test @MainActor func actualCoreSevenRowWorkflowFiltersDetailsAndStaleInput() async throws {
        let model=Workspace(clientFactory:{ DirectCoreWorker() })
        model.rootA = "env"; model.rootB = "env"
        model.a="var devConfig={DEBUG:true};var env={a:1,b:2,c:3,port:3000,redis:{host:'cache-a',port:6379}};module.exports=env;"
        model.b="var devConfig={DEBUG:false};var env={redis:{port:6379,host:'cache-b'},port:'3000',c:30,a:1,d:4};module.exports=env;"
        model.run()
        try await settled(model) { !model.busy && model.matched == 5 }
        #expect(model.summary?.total == 7)
        #expect(model.summary?.differences == 5)
        #expect(model.summary?.same == 2)
        #expect(model.complete && !model.stale && !model.error)
        let summary=model.summary?.total
        model.filter="SAME"; model.loadRows(reset:true)
        try await settled(model) {model.matched == 2}
        #expect(model.rows.allSatisfy { $0.status == "SAME" })
        #expect(model.summary?.total == summary)
        model.filter="all"; model.search="cache-b"; model.searchScope="value"; model.loadRows(reset:true)
        try await settled(model) {model.matched == 1}
        model.selected=model.rows.first?.id; model.inspectSelection()
        try await settled(model) {model.detail != nil}
        #expect(model.detail?.b.literal == "\"cache-b\"")
        model.a="var env={changed:1};"; model.changed(side:true)
        #expect(model.stale && model.detail == nil && model.selected == nil)
        #expect(model.summary?.total == 7)
        #expect(model.notice.contains("过期"))
        model.cancel()
    }

    @Test @MainActor func unknownDiagnosticsSurviveFilteringAndParseErrorCanRecover() async throws {
        let model=Workspace(clientFactory:{ DirectCoreWorker() })
        model.a="var env={...outside,fixed:1};"; model.b=model.a
        model.run()
        try await settled(model) {!model.busy && model.summary != nil}
        #expect(!model.complete && !model.incomplete.isEmpty)
        model.filter="SAME"; model.loadRows(reset:true)
        try await settled(model) {model.matched == 1}
        #expect(!model.complete && !model.incomplete.isEmpty)
        model.a="var env={"; model.changed(side:true); model.run()
        try await settled(model) {!model.busy && model.error}
        #expect(model.a == "var env={")
        #expect(model.summary == nil)
        #expect(model.notice.contains("JS_PARSE_ERROR"))
        model.a="var env={fixed:1};"; model.b=model.a; model.changed(); model.run()
        try await settled(model) {!model.busy && model.summary?.same == 1}
        #expect(!model.error && model.complete)
        model.cancel()
    }

    @Test @MainActor func yamlSuccessErrorAndToolSwitchRetainPrivacyContracts() async throws {
        let model=Workspace(clientFactory:{ DirectCoreWorker() })
        model.tool = .yaml; model.switchTool()
        model.a="# synthetic\nbase: &x {port:  3000}\ncopy: *x\ntext: '001'\n"
        let original=model.a
        model.run()
        try await settled(model) {!model.busy && !model.output.isEmpty}
        #expect(model.a == original)
        #expect(model.output.contains("# synthetic") && model.output.contains("&x") && model.output.contains("'001'"))
        model.a="a: 1\na: 2\n"; model.changed(side:true)
        #expect(model.stale)
        model.run()
        try await settled(model) {!model.busy && model.error}
        #expect(model.notice.contains("YAML_DUPLICATE_KEY"))
        #expect(model.a == "a: 1\na: 2\n" && model.output.isEmpty)
        model.vaultA.token="synthetic-token"; model.vaultA.confirmedNonProduction=true
        model.tool = .env; model.switchTool()
        #expect(model.a.isEmpty && model.b.isEmpty && model.output.isEmpty)
        #expect(model.vaultA.token.isEmpty && !model.vaultA.confirmedNonProduction)
        #expect(model.summary == nil && model.detail == nil && model.rows.isEmpty)
    }

    @Test @MainActor func vaultEditingIsIdlePreviewReadsNoValuesAndRunUsesFixedPlans() async throws {
        let transport=FixtureVault()
        let model=Workspace(clientFactory:{ DirectCoreWorker() },vaultFactory:{ VaultReader(transport:transport,validate:$0) })
        model.tool = .vault; model.switchTool()
        var a=VaultSettings(); a.url="https://uat.example.invalid"; a.mount="secret"
        a.token="synthetic-token"; a.environment="uat-swim"; a.confirmedNonProduction=true
        model.vaultA=a; a.environment="qat-other"; model.vaultB=a
        #expect(await transport.requests.isEmpty)
        model.run()
        #expect(model.error && !model.busy)
        #expect(await transport.requests.isEmpty)
        model.previewVault()
        try await settled(model) {!model.busy && model.vaultPlanB != nil}
        #expect(model.vaultPlanA?.secrets.count == 2)
        #expect(await transport.requests.allSatisfy { !$0.url!.path.contains("/data/") })
        model.run()
        try await settled(model) {!model.busy && model.summary?.total == 4}
        #expect(model.summary?.typeChanged == 2 && model.summary?.same == 2)
        #expect(model.vaultCaptureInfo.count == 2)
        #expect(!model.vaultCaptureInfo.description.contains("synthetic-token"))
        let old=model.vaultA
        model.vaultA.environment="new-name"
        model.vaultChanged(side:true,old:old,new:model.vaultA)
        #expect(model.stale && model.vaultPlanA == nil && model.vaultPlanB == nil)
        let count=await transport.requests.count
        model.run()
        #expect(await transport.requests.count == count)
        model.cancel()
    }

    @Test @MainActor func failedFileImportKeepsCurrentTextAndRemoteURLsAreRejected() async throws {
        let model=Workspace(clientFactory:{ DirectCoreWorker() })
        model.a="var env={existing:1};"
        model.importFile(URL(string:"https://uat.example.invalid/env.js")!,side:true)
        #expect(model.error && model.a == "var env={existing:1};")
        model.error=false
        model.importFile(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),side:true)
        try await settled(model) {model.error}
        #expect(model.a == "var env={existing:1};")
        model.cancel()
    }

    @Test @MainActor func exchangingFileInputsMovesRootsLabelsAndDifferenceDirection() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let first=dir.appendingPathComponent("left.js"), second=dir.appendingPathComponent("right.js")
        try Data("var alpha={left:1};".utf8).write(to:first)
        try Data("var beta={right:2};".utf8).write(to:second)
        let model=Workspace(clientFactory:{DirectCoreWorker()})
        model.importFile(first,side:true); model.importFile(second,side:false)
        try await settled(model) {model.fileA == first && model.fileB == second}
        model.rootA="alpha"; model.rootB="beta"; model.rootsA=["alpha"]; model.rootsB=["beta"]
        model.inputTypeA="kv-v1-response"; model.inputTypeB="kv-v2-response"
        model.run()
        try await settled(model) {!model.busy && model.matched == 2}
        #expect(model.rows.first(where:{$0.path == "$.left"})?.status == "ONLY_A")
        model.selected=model.rows.first?.id; model.inspectSelection()
        try await settled(model) {model.detail != nil}
        model.swapSides()
        #expect(model.stale && model.detail == nil && model.selected == nil)
        #expect(model.fileA == second && model.fileB == first)
        #expect(model.labelA == "A · right.js" && model.labelB == "B · left.js")
        #expect(model.rootA == "beta" && model.rootB == "alpha")
        #expect(model.rootsA == ["beta"] && model.rootsB == ["alpha"])
        #expect(model.inputTypeA == "kv-v2-response" && model.inputTypeB == "kv-v1-response")
        model.run()
        try await settled(model) {!model.busy && !model.stale && model.matched == 2}
        #expect(model.rows.first(where:{$0.path == "$.left"})?.status == "ONLY_B")
        #expect(model.rows.first(where:{$0.path == "$.right"})?.status == "ONLY_A")
        model.cancel()
    }

    @Test @MainActor func exchangingVaultScopesRequiresFreshConfirmationAndMakesNoRequests() async throws {
        let transport=FixtureVault()
        let model=Workspace(clientFactory:{DirectCoreWorker()},vaultFactory:{VaultReader(transport:transport,validate:$0)})
        model.tool = .vault; model.switchTool()
        var first=VaultSettings(); first.url="https://uat.example.invalid"; first.mount="secret"
        first.token="synthetic-left"; first.environment="uat-swim"; first.confirmedNonProduction=true
        var second=first; second.url="https://qat.example.invalid"; second.token="synthetic-right"; second.environment="qat-other"
        model.vaultA=first; model.vaultB=second
        model.previewVault()
        try await settled(model) {!model.busy && model.vaultPlanB != nil}
        let count=await transport.requests.count
        model.swapSides()
        #expect(model.vaultA.url == "https://qat.example.invalid" && model.vaultB.url == "https://uat.example.invalid")
        #expect(model.vaultA.token == "synthetic-right" && model.vaultB.token == "synthetic-left")
        #expect(model.vaultA.environment == "qat-other" && model.vaultB.environment == "uat-swim")
        #expect(!model.vaultA.confirmedNonProduction && !model.vaultB.confirmedNonProduction)
        #expect(model.vaultPlanA == nil && model.vaultPlanB == nil && model.vaultCaptureInfo.isEmpty)
        #expect(await transport.requests.count == count)
        model.run()
        #expect(model.error)
        #expect(await transport.requests.count == count)
        model.cancel()
    }

    @Test @MainActor func exchangeIsUnavailableDuringWorkAndForSingleInputYAML() {
        let model=Workspace(clientFactory:{DirectCoreWorker()})
        model.a="first"; model.b="second"; model.busy=true
        model.swapSides()
        #expect(model.a == "first" && model.b == "second")
        model.busy=false; model.tool = .yaml
        model.swapSides()
        #expect(model.a == "first" && model.b == "second")
    }
}
