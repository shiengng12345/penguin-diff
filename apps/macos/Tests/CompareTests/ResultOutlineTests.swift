import Foundation
import Testing
import CompareShared
import CoreBridge
@testable import CompareUI

private func outlineCore(_ request: [String: Any]) throws -> CoreResponse {
    let text = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
    return try CoreResponse.decode(CoreBridge.process(text))
}
private func outlineNodes(_ roots: [ResultOutlineNode]) -> [ResultOutlineNode] {
    roots.flatMap { [$0] + outlineNodes($0.children ?? []) }
}
private func outlineReport(_ session: String) throws -> String {
    let request = String(decoding: try JSONSerialization.data(withJSONObject: ["op":"report", "session":session]), as: UTF8.self)
    return CoreBridge.process(request)
}

@Suite(.serialized) struct ResultOutlineTests {
    @Test @MainActor func variableNamesKeepSpecialKeysIdentityAndReports() throws {
        let session = UUID().uuidString
        defer { _ = try? outlineCore(["op":"release", "session":session]) }
        let source = #"var env={x:2,auth:{host:'local'},items:[1],'a.b':3,a:{b:4},'':5,'$.x':6,'\ud800':7};"#
        let result = try outlineCore(["op":"compare", "kind":"js", "session":session, "a":source, "b":source])
        let rows = try #require(result.rows)
        let report = try outlineReport(session)
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.rootA = "env"; model.rootB = "env"
        let names = rows.map { model.resultName($0.path) }
        #expect(names.contains("x") && names.contains("auth.host") && names.contains("items[0]"))
        #expect(names.contains(#"["a.b"]"#) && names.contains("a.b"))
        #expect(names.contains(#"[""]"#) && names.contains(#"["$.x"]"#) && names.contains(#"["\ud800"]"#))
        #expect(Set(names).count == rows.count)
        let nodes = outlineNodes(ResultOutline.build(rows))
        #expect(nodes.contains { model.resultName($0.path) == "auth" && $0.row == nil })
        #expect(nodes.compactMap(\.row).map(\.id) == rows.map(\.id))
        #expect(model.resultName("$") == "env")
        model.rootA = "config"; model.rootB = "config"
        #expect(model.resultName("$") == "config")
        model.rootB = "module.exports"
        #expect(model.resultName("$") == "比较根")
        model.preferences.language = .english
        #expect(model.resultName("$") == "Comparison root")
        model.tool = .vault
        #expect(rows.map { model.resultName($0.path) } == rows.map(\.path))
        #expect(model.resultName(#"$["."].auth.PORT"#) == "$.auth.PORT")
        #expect(model.resultName(#"$["team"].auth.PORT"#) == #"$["team"].auth.PORT"#)
        #expect(try outlineReport(session) == report)
    }

    @Test func deepDisjointPathsKeepEveryPrefixAndRealCoreRow() throws {
        let session = UUID().uuidString
        defer { _ = try? outlineCore(["op":"release", "session":session]) }
        var nested = "1"
        for level in (1..<120).reversed() { nested = "{\"level\(level)\":\(nested)}" }
        let source = "{" + (0..<200).map { "\"branch\($0)\":" + nested }.joined(separator: ",") + "}"
        let result = try outlineCore(["op":"compare", "kind":"json", "a":source, "b":source, "session":session])
        let before = try outlineReport(session)
        let rows = try #require(result.rows)
        let roots = ResultOutline.build(rows)
        #expect(result.summary?.total == 200 && result.summary?.same == 200 && result.complete == true)
        #expect(roots.count == 200)
        var ids = Set<ResultOutlineID>(), leaves = Set<Int>()
        for root in roots {
            var node = root, expected = root.path
            #expect(root.resultCount == 1 && root.row == nil)
            ids.insert(root.id)
            for level in 1..<120 {
                let children = try #require(node.children)
                #expect(children.count == 1)
                node = children[0]; expected += ".level\(level)"
                #expect(node.path == expected && node.resultCount == 1)
                ids.insert(node.id)
            }
            let row = try #require(node.row)
            #expect(row.path == expected && row.segments?.count == 120 && node.children == nil)
            leaves.insert(row.id)
        }
        #expect(ids.count == 24_000 && leaves == Set(rows.map(\.id)))
        #expect(try outlineReport(session) == before)
    }

    @Test func nestedProjectionKeepsOriginalRowsCountsAndReport() throws {
        let session = UUID().uuidString
        defer { _ = try? outlineCore(["op":"release", "session":session]) }
        let result = try outlineCore(["op":"compare", "kind":"json", "session":session,
            "a":#"{"nested":{"left":1,"right":2},"list":[null,{"k":1}],"empty":{}}"#,
            "b":#"{"nested":{"left":1,"right":3},"list":[true,{"k":1}],"empty":{}}"#])
        let before = try outlineReport(session)
        let rows = try #require(result.rows)
        let tree = ResultOutline.build(rows)
        let nodes = outlineNodes(tree)
        #expect(result.summary?.total == 5 && result.summary?.differences == 2)
        #expect(tree.reduce(0) { $0 + $1.resultCount } == 5)
        #expect(nodes.compactMap(\.row).map(\.id) == rows.map(\.id))
        #expect(nodes.compactMap(\.row).map(\.path) == rows.map(\.path))
        #expect(nodes.first(where: { $0.path == "$.nested" })?.resultCount == 2)
        #expect(nodes.first(where: { $0.path == "$.list[1]" })?.row == nil)
        #expect(try outlineReport(session) == before)
    }

    @Test func machineIdentityDoesNotMergeSpecialOrCanonicallyEquivalentKeys() throws {
        let session = UUID().uuidString
        defer { _ = try? outlineCore(["op":"release", "session":session]) }
        let source = #"{"a.b":1,"a":{"b":2},"":3,"\ud800":4,"\ufffd":5,"é":6,"e\u0301":7,"obj":{"0":1},"arr":[1]}"#
        let result = try outlineCore(["op":"compare", "kind":"json", "a":source, "b":source, "session":session])
        let nodes = outlineNodes(ResultOutline.build(try #require(result.rows)))
        #expect(nodes.compactMap(\.row).count == 9)
        #expect(Set(nodes.map(\.id)).count == nodes.count)
        #expect(OutlinePath.display([.key([55296])]) == #"$["\ud800"]"#)
        #expect(OutlinePath.display([.key(Array("中文😀".utf16))]) == #"$["中文😀"]"#)
        #expect(OutlinePath.display([.key([0,34,92,10])]) == #"$["\u0000\"\\\n"]"#)
        #expect(OutlinePath.display([.key([48])]) != OutlinePath.display([.index(0)]))
        #expect(nodes.contains(where: { $0.path == #"$["a.b"]"# }))
        #expect(nodes.contains(where: { $0.path == "$.a.b" }))
    }

    @Test @MainActor func unicodeGroupedPathsMatchCoreDisplay() throws {
        let session = UUID().uuidString
        defer { _ = try? outlineCore(["op":"release", "session":session]) }
        let source = #"{"plain":1,"é":{"child":2},"中文":{"child":3},"e\u0301":4,"a.b":5}"#
        let result = try outlineCore(["op":"compare", "kind":"json", "a":source, "b":source, "session":session])
        let rows = try #require(result.rows)
        let nodes = outlineNodes(ResultOutline.build(rows))
        func units(_ value: String) -> [UInt16] { Array(value.utf16) }
        let branchPathUnits = Set(nodes.filter { $0.row == nil }.map { units($0.path) })
        let rowPathUnits = Set(rows.map { units($0.path) })
        #expect(rowPathUnits == Set([
            units("$.plain"), units(#"$["a.b"]"#), units(#"$["é"]"#),
            units(#"$["é"].child"#), units(#"$["中文"].child"#)
        ]))
        #expect(branchPathUnits.contains(units(#"$["é"]"#)) && branchPathUnits.contains(units(#"$["中文"]"#)))
        #expect(!rowPathUnits.contains(units("$.é")) && !rowPathUnits.contains(units("$.中文")))
        #expect(!branchPathUnits.contains(units("$.é")) && !branchPathUnits.contains(units("$.中文")))
        let precomposedBranch = try #require(nodes.first {
            $0.row == nil && units($0.path) == units(#"$["é"]"#)
        })
        #expect(precomposedBranch.children?.count == 1)
        #expect(precomposedBranch.children?.first.map { units($0.path) } == units(#"$["é"].child"#))
        #expect(nodes.contains { $0.row != nil && units($0.path) == units(#"$["é"]"#) })
    }

    @Test func containerDetailsExpandWithoutAddingComparisonResults() throws {
        let session = UUID().uuidString
        defer { _ = try? outlineCore(["op":"release", "session":session]) }
        let result = try outlineCore(["op":"compare", "kind":"js", "session":session,
            "a":#"var env={blob:{s:'\ud800',n:-0,b:9007199254740993n,u:undefined,arr:[,undefined],unknown:process.env.KEY}};"#,
            "b":"var env={};"])
        let before = try outlineReport(session)
        let row = try #require(try outlineCore(["op":"details", "session":session, "id":0]).row)
        let children = ValueOutline.children(of: row.a)
        #expect(result.summary?.total == 1 && result.summary?.onlyA == 1 && result.complete == false)
        #expect(children.count == 6)
        #expect(children.first(where: { $0.path == "$.s" })?.value.units == [55296])
        #expect(children.first(where: { $0.path == "$.b" })?.value.literal == "9007199254740993n")
        #expect(children.first(where: { $0.path == "$.arr" })?.children?.map(\.value.type) == ["Hole", "Undefined"])
        #expect(children.first(where: { $0.path == "$.unknown" })?.value.reason != nil)
        #expect(ValueOutline.children(of: row.b).isEmpty)
        #expect(try outlineReport(session) == before)
    }

    @Test func paginationAndFilteringOnlyGroupTheReturnedPage() throws {
        let session = UUID().uuidString
        defer { _ = try? outlineCore(["op":"release", "session":session]) }
        let a = Dictionary(uniqueKeysWithValues: (0..<450).map { (String(format:"k%03d",$0),$0) })
        let b = Dictionary(uniqueKeysWithValues: (0..<450).map { (String(format:"k%03d",$0),$0 + ($0 % 2)) })
        func input(_ fields: [String:Int]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: ["bundle":fields]), as: UTF8.self)
        }
        let compared = try outlineCore(["op":"compare", "kind":"json", "a":try input(a), "b":try input(b), "session":session])
        let before = try outlineReport(session)
        for offset in [0,200] {
            let page = try outlineCore(["op":"rows", "session":session, "filter":"VALUE_CHANGED", "offset":offset, "limit":200])
            let nodes = ResultOutline.build(try #require(page.rows))
            #expect(page.matched == 225)
            #expect(nodes.count == 1 && nodes[0].resultCount == (offset == 0 ? 200 : 25))
            #expect(outlineNodes(nodes).compactMap(\.row).allSatisfy { $0.status == "VALUE_CHANGED" })
        }
        #expect(compared.summary?.total == 450 && compared.summary?.same == 225)
        #expect(try outlineReport(session) == before)
    }

    @Test func missingMachinePathRemainsAnUnparsedLeafAndEmptyPageHasNoGroups() throws {
        let row = try JSONDecoder().decode(ResultRow.self, from: Data(#"{"id":19,"path":"$.do.not.guess[0]","status":"ONLY_A","a":{"type":"Object","display":"{ 0 个键 }","present":true},"b":{"type":"Missing","display":"<不存在>","present":false}}"#.utf8))
        let tree = ResultOutline.build([row])
        #expect(tree.count == 1 && tree[0].id == .result(19) && tree[0].children == nil)
        #expect(tree[0].path == row.path && tree[0].resultCount == 1)
        #expect(ResultOutline.build([]).isEmpty)
    }

    @Test func emptyRootContainersStayAsOneVisibleResult() throws {
        let session = UUID().uuidString
        defer { _ = try? outlineCore(["op":"release", "session":session]) }
        let result = try outlineCore(["op":"compare", "kind":"json", "a":"{}", "b":"{}", "session":session])
        let tree = ResultOutline.build(try #require(result.rows))
        #expect(tree.count == 1 && tree[0].path == "$" && tree[0].children == nil && tree[0].resultCount == 1)
        #expect(result.summary?.total == 1 && result.summary?.same == 1)
    }

    @Test func valueTreePreviewIsBoundedByUnicodeScalarsRatherThanCombinedCharacters() throws {
        let session = UUID().uuidString
        defer { _ = try? outlineCore(["op":"release", "session":session]) }
        let source = "var env={blob:{long:'" + String(repeating: "e\u{0301}", count: 400) + "'}};"
        _ = try outlineCore(["op":"compare", "kind":"js", "a":source, "b":"var env={};", "session":session])
        let side = try #require(try outlineCore(["op":"details", "session":session, "id":0]).row?.a)
        let node = try #require(ValueOutline.children(of: side).first)
        #expect(node.preview.unicodeScalars.count == 241 && node.preview.hasSuffix("…"))
        #expect(node.value.literal.unicodeScalars.count == 802)
    }
}
