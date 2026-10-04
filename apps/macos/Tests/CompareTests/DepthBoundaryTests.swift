import Foundation
import Testing
import CompareShared
import CoreBridge
@testable import CompareUI

private func depthCall(_ fields: [String:Any], acceptingError: Bool = false) throws -> CoreResponse {
    let request = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    let raw = CoreBridge.process(request)
    if acceptingError { return try JSONDecoder().decode(CoreResponse.self, from: Data(raw.utf8)) }
    return try CoreResponse.decode(raw)
}
private func depthSource(_ depth: Int, arrays: Bool, leaf: String = "1") -> String {
    if arrays { return "{\"field\":" + String(repeating:"[",count:depth-1) + leaf + String(repeating:"]",count:depth-1) + "}" }
    return String(repeating:"{\"field\":",count:depth) + leaf + String(repeating:"}",count:depth)
}
private func depthInput(_ text: String, kind: String) -> String { kind == "js" ? "var env=" + text + ";" : text }

@Suite(.serialized) struct DepthBoundaryTests {
    @Test func depth128RowsProjectAndReleaseOnTheOrdinaryTestThread() throws {
        for kind in ["json","js"] {
            for arrays in [false,true] {
                let session = UUID().uuidString
                let source = depthInput(depthSource(128,arrays:arrays),kind:kind)
                do {
                    let result = try depthCall(["op":"compare","kind":kind,"a":source,"b":source,"session":session])
                    let rows = try #require(result.rows)
                    #expect(result.complete == true && result.summary?.total == 1 && result.summary?.same == 1)
                    var nodes = ResultOutline.build(rows), count = 0
                    while let node = nodes.first {
                        #expect(nodes.count == 1 && node.resultCount == 1)
                        count += 1
                        if let row = node.row {
                            #expect(row.segments?.count == 128 && row.status == "SAME" && row.a.type == "Number")
                        }
                        nodes = node.children ?? []
                    }
                    #expect(count == 128)
                }
                #expect(try depthCall(["op":"release","session":session]).ok)
                #expect(try depthCall(["op":"rows","session":session],acceptingError:true).error?.code == "SESSION_NOT_FOUND")
            }
        }
        let recovery = try depthCall(["op":"compare","kind":"json","a":"{}","b":"{}","session":"depth-row-recovery"])
        #expect(recovery.summary?.same == 1)
        _ = try depthCall(["op":"release","session":"depth-row-recovery"])
    }

    @Test func depth129NeverCreatesAComparisonSessionAndCanRecover() throws {
        for kind in ["json","js"] {
            for arrays in [false,true] {
                let session = UUID().uuidString
                let source = depthInput(depthSource(129,arrays:arrays),kind:kind)
                let failure = try depthCall(["op":"compare","kind":kind,"a":source,"b":source,"session":session],acceptingError:true)
                #expect(!failure.ok && failure.error?.code == "RESOURCE_LIMIT" && failure.rows == nil && failure.summary == nil)
                #expect(try depthCall(["op":"report","session":session],acceptingError:true).error?.code == "SESSION_NOT_FOUND")
                let small = depthInput("{}",kind:kind)
                #expect(try depthCall(["op":"compare","kind":kind,"a":small,"b":small,"session":session]).summary?.same == 1)
                _ = try depthCall(["op":"release","session":session])
            }
        }
    }

    @Test func depth128ContainerDetailsKeepExactNumbersAndUTF16() throws {
        for (kind, leaf, type, literal, units) in [
            ("json","9007199254740993","Number","9007199254740993",nil as [UInt16]?),
            ("js","9007199254740993n","BigInt","9007199254740993n",nil),
            ("json",#""\ud800""#,"String",#""\ud800""#,[55296]),
            ("js",#"'\ud800'"#,"String",#""\ud800""#,[55296])
        ] {
            for arrays in [false,true] {
                let session = UUID().uuidString
                defer { _ = try? depthCall(["op":"release","session":session]) }
                let source = depthInput(depthSource(128,arrays:arrays,leaf:leaf),kind:kind)
                let compared = try depthCall(["op":"compare","kind":kind,"a":source,"b":depthInput("{}",kind:kind),"session":session])
                #expect(compared.complete == true && compared.summary?.total == 1 && compared.summary?.onlyA == 1)
                let row = try #require(try depthCall(["op":"details","session":session,"id":0]).row)
                #expect(row.segments == [.key(Array("field".utf16))])
                var nodes = ValueOutline.children(of:row.a), count = 0
                while let node = nodes.first {
                    #expect(nodes.count == 1)
                    count += 1
                    if node.children == nil {
                        #expect(node.value.type == type && node.value.literal == literal && node.value.units == units)
                        #expect(node.id.count == 127)
                    }
                    nodes = node.children ?? []
                }
                #expect(count == 127)
            }
        }
    }

    @Test func yaml128ContainersFormatBut129FailWithoutOutput() throws {
        let source = { (depth: Int) in String(repeating:"[",count:depth) + "1" + String(repeating:"]",count:depth) + "\n" }
        let formatted = try #require(try depthCall(["op":"formatYaml","source":source(128)]).text)
        #expect(formatted.filter { $0 == "[" }.count == 128 && formatted.filter { $0 == "]" }.count == 128)
        #expect(try depthCall(["op":"formatYaml","source":formatted]).text == formatted)
        let rejected = try depthCall(["op":"formatYaml","source":source(129)],acceptingError:true)
        #expect(!rejected.ok && rejected.error?.code == "RESOURCE_LIMIT" && rejected.text == nil)
        #expect(try depthCall(["op":"formatYaml","source":"x:  1\n"]).text == "x: 1\n")
    }
}
