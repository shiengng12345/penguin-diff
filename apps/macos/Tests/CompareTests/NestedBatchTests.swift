import Foundation
import Testing
import MCP
@testable import CompareUI

private let nestedBatchA = #"""
var env={api:{timeout:30,retries:{max:3,enabled:true}},servers:[{host:'a',tls:{enabled:true}},{host:'b',tls:{enabled:false}}],shape:{inner:{flag:true}},empty:{}};
var happy={options:{cache:{enabled:true,ttl:60},api:{timeout:30}},labels:{'a.b':{value:1},a:{b:{value:9}}}};
"""#
private let nestedBatchB = #"""
var happy={labels:{a:{b:{value:9}},'a.b':{value:2}},options:{api:{timeout:30},cache:{grace:7,enabled:true}}};
var env={empty:{},shape:'disabled',servers:[{tls:{enabled:false},host:'a'},{tls:{enabled:false},host:'b'}],api:{retries:{enabled:true,max:'3'},timeout:45}};
"""#
private let nestedBatchExpected = [
    "env.api.timeout": "VALUE_CHANGED", "env.api.retries.max": "TYPE_CHANGED",
    "env.api.retries.enabled": "SAME", "env.servers[0].host": "SAME",
    "env.servers[0].tls.enabled": "VALUE_CHANGED", "env.servers[1].host": "SAME",
    "env.servers[1].tls.enabled": "SAME", "env.shape": "TYPE_CHANGED",
    "env.empty": "SAME", "happy.options.cache.enabled": "SAME",
    "happy.options.cache.ttl": "ONLY_A", "happy.options.cache.grace": "ONLY_B",
    "happy.options.api.timeout": "SAME", #"happy.labels["a.b"].value"#: "VALUE_CHANGED",
    "happy.labels.a.b.value": "SAME"
]

@Suite(.serialized) struct NestedBatchTests {
    @Test @MainActor func workspaceComparesDeepBranchesInEveryVariableAndKeepsTreeIdentity() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        defer { model.cancel() }
        model.a = nestedBatchA; model.b = nestedBatchB
        model.run()
        let deadline = ContinuousClock.now + .seconds(3)
        while (model.busy || model.matched != 7), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(!model.busy && model.matched == 7)
        model.filter = "all"; model.loadRows(reset: true)
        while (model.busy || model.matched != 15), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(!model.busy && model.matched == 15 && model.rows.count == 15, "Nested comparison did not settle: \(model.notice)")
        #expect(model.complete && model.summary?.total == 15 && model.summary?.same == 8 && model.summary?.differences == 7)
        #expect(Dictionary(uniqueKeysWithValues: model.rows.map { (model.resultName($0.path), $0.status) }) == nestedBatchExpected)
        func nodes(_ roots: [ResultOutlineNode]) -> [ResultOutlineNode] {
            roots.flatMap { [$0] + nodes($0.children ?? []) }
        }
        let tree = ResultOutline.build(model.rows)
        let flattened = nodes(tree)
        #expect(tree.count == 2 && tree.reduce(0) { $0 + $1.resultCount } == 15)
        #expect(Set(flattened.compactMap(\.row).map(\.id)) == Set(model.rows.map(\.id)))
        #expect(Set(flattened.map(\.id)).count == flattened.count)
        #expect(flattened.contains { $0.path == "$.env.servers[0].tls" && $0.row == nil })
        #expect(flattened.contains { $0.path == "$.happy.options.cache" && $0.resultCount == 3 })
        // A changed container type is one result at its parent, not invented missing children.
        #expect(!model.rows.contains { $0.path.hasPrefix("$.env.shape.") })
        model.selected = try #require(model.rows.first { $0.path == "$.env.api.retries.max" }).id
        model.inspectSelection()
        let detailDeadline = ContinuousClock.now + .seconds(3)
        while model.detail == nil, ContinuousClock.now < detailDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let detail = try #require(model.detail)
        #expect(detail.a.literal == "3" && detail.b.literal == #""3""#)
    }

    @Test @MainActor func mcpDefaultsToNestedBatchAndPagesAllPathsWithoutValues() async throws {
        let service = MCPService(workerFactory: { DirectCoreWorker() })
        func json(_ result: CallTool.Result) throws -> [String: Any] {
            try #require(result.isError != true)
            let text = result.content.compactMap { item in
                if case .text(let text, _, _) = item { return text }; return nil
            }.joined()
            return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }
        let first = try json(await service.call(name: "env_compare", arguments: ["a": .string(nestedBatchA), "b": .string(nestedBatchB)]))
        let summary = try #require(first["summary"] as? [String: Int])
        #expect(summary["total"] == 15 && summary["same"] == 8 && summary["differences"] == 7)
        let differences = try #require(first["rows"] as? [[String: Any]])
        #expect(differences.count == 7 && differences.allSatisfy { $0["status"] as? String != "SAME" })
        let session = try #require(first["session"] as? String)
        let all = try json(await service.call(name: "comparison_rows", arguments: ["session": .string(session), "filter": .string("all")]))
        let rows = try #require(all["rows"] as? [[String: Any]])
        #expect(rows.count == 15 && all["includesValues"] as? Bool == false)
        var actual: [String: String] = [:]
        for row in rows {
            let path = try #require(row["path"] as? String)
            actual[String(path.dropFirst(2))] = try #require(row["status"] as? String)
            for side in ["a", "b"] {
                let value = try #require(row[side] as? [String: Any])
                #expect(Set(value.keys) == ["type", "present", "display"])
                #expect(value["display"] as? String == "<值未导出>")
            }
        }
        #expect(actual == nestedBatchExpected)
    }
}
