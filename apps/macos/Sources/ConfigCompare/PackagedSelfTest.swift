import Foundation
import AppKit
import CompareShared

// Headless packaged XPC verification: never construct the SwiftUI App.
public enum PackagedSelfTest {
    @MainActor public static func run() async -> Int32 {
        guard (NSApp?.windows.count ?? 0) == 0 else { return 18 }
        let client = WorkerClient()
        defer { client.abort() }
        do {
            let sample = "{\"op\":\"compare\",\"kind\":\"json\",\"a\":\"{\\\"p\\\":3000}\",\"b\":\"{\\\"p\\\":\\\"3000\\\"}\",\"session\":\"self-test\"}"
            let response = try CoreResponse.decode(try await client.send(sample))
            guard response.summary?.typeChanged == 1, response.complete == true else { return 2 }
            let yaml = try CoreResponse.decode(try await client.send("{\"op\":\"formatYaml\",\"source\":\"x:  1\\n\"}"))
            guard yaml.text == "x: 1\n" else { return 3 }
            func compareJS(_ a: String, _ b: String) async throws -> CoreResponse {
                let data = try JSONSerialization.data(withJSONObject: ["op":"compare", "kind":"js", "a":a, "b":b, "session":UUID().uuidString])
                return try CoreResponse.decode(try await client.send(String(decoding:data,as:UTF8.self)))
            }
            let continuation = try await compareJS("var env={x:'a\\\u{2028}b'};", "var env={x:'ab'};")
            guard continuation.summary?.same == 1 else { return 4 }
            let prototype = try await compareJS("var env={f:[].map};", "var env={f:undefined};")
            guard prototype.summary?.notComparable == 1, prototype.complete == false else { return 5 }
            let discarded = try await compareJS("null.x;var env={a:1};", "var env={a:1};")
            guard discarded.complete == false else { return 6 }
            let numbers = try await compareJS("var env={a:Infinity,c:1e21};", "var env={};")
            guard numbers.rows?.first?.a.display == "Infinity", numbers.rows?.last?.a.display == "1e+21" else { return 7 }
            let invalid = try JSONSerialization.data(withJSONObject: ["op":"compare", "kind":"json", "a":#"{"k":"\u+041"}"#, "b":"{}"])
            do {
                _ = try CoreResponse.decode(try await client.send(String(decoding:invalid,as:UTF8.self)))
                return 8
            } catch let failure as CoreError { guard failure.code == "JSON_PARSE_ERROR" else { return 9 } }
            do {
                _ = try await compareJS("let env={a:1};if(false)var env={a:2};", "var env={a:1};")
                return 10
            } catch let failure as CoreError { guard failure.code == "UNSUPPORTED_SEMANTICS" else { return 11 } }
            let treeInput = "\u{FEFF}" + #"{"blob":{"\ud800":"\ud800","nested":[-0,9007199254740993,1e10000,{"\udfff":true}]}}"#
            let treeRequest = try JSONSerialization.data(withJSONObject: ["op":"compare", "kind":"json", "a":treeInput, "b":"{}", "session":"self-test-json-tree"])
            let tree = try CoreResponse.decode(try await client.send(String(decoding:treeRequest,as:UTF8.self)))
            guard tree.summary?.onlyA == 1 else { return 12 }
            let treeDetail = try CoreResponse.decode(try await client.send(#"{"op":"details","session":"self-test-json-tree","id":0}"#))
            guard let row = treeDetail.row, row.segments == [.key(Array("blob".utf16))],
                  row.a.entries?.first(where: { $0.keyUnits == [55296] })?.value.units == [55296],
                  let items = row.a.entries?.first(where: { $0.keyUnits == Array("nested".utf16) })?.value.items,
                  items.count == 4,
                  items.prefix(3).map(\.literal) == ["-0","9007199254740993","1e10000"],
                  items[3].entries?.first?.keyUnits == [57343] else { return 13 }
            let bom = try await compareJS("\u{FEFF}var env={中文:'值'};", "var env={中文:'值'};")
            guard bom.rows?.first?.a.column == 20, bom.rows?.first?.b.column == 17 else { return 14 }
            let special = try await compareJS(#"var env={blob:{s:'\udfff',big:9007199254740993n,u:undefined,a:[,undefined]}};"#, "var env={};")
            let specialRequest = try JSONSerialization.data(withJSONObject: ["op":"details", "session":special.session ?? "", "id":0])
            let specialDetail = try CoreResponse.decode(try await client.send(String(decoding:specialRequest,as:UTF8.self)))
            guard let entries = specialDetail.row?.a.entries,
                  entries.first(where: { $0.keyUnits == [115] })?.value.units == [57343],
                  entries.first(where: { $0.keyUnits == Array("big".utf16) })?.value.literal == "9007199254740993n",
                  entries.first(where: { $0.keyUnits == [117] })?.value.type == "Undefined",
                  entries.first(where: { $0.keyUnits == [97] })?.value.items?.map(\.type) == ["Hole","Undefined"] else { return 15 }
            let grouped = try await compareJS("var env={nested:{a:1,b:2},arr:[1,2]};", "var env={nested:{a:1,b:3},arr:[1,4]};")
            let outline = ResultOutline.build(grouped.rows ?? [])
            let valueTree = ValueOutline.children(of: row.a)
            guard grouped.summary?.total == 4, grouped.summary?.differences == 2,
                  outline.count == 2, outline.allSatisfy({ $0.row == nil && $0.resultCount == 2 }),
                  valueTree.first(where: { $0.id == [.key([55296])] })?.value.units == [55296],
                  valueTree.first(where: { $0.path == "$.nested" })?.children?.prefix(3).map(\.value.literal) == ["-0","9007199254740993","1e10000"] else { return 16 }
            let provenanceRequest = try JSONSerialization.data(withJSONObject: ["op":"inspectVaultRead", "kvVersion":2, "httpStatus":200, "source":#"{"data":{"data":{"n":1e10000,"s":"\ud800"},"metadata":{"version":9007199254740993,"created_time":"2026-10-03T01:02:03.123456789Z","deletion_time":"","destroyed":false}}}"#])
            let provenance = try CoreResponse.decode(try await client.send(String(decoding:provenanceRequest,as:UTF8.self)))
            guard provenance.vaultMetadata?.version == "9007199254740993", provenance.vaultMetadata?.kvVersion == 2,
                  provenance.text?.contains("1e10000") == true, provenance.text?.contains("\\ud800") == true else { return 17 }
            guard (NSApp?.windows.count ?? 0) == 0 else { return 18 }
            print("PACKAGED_SELF_TEST_WINDOW_COUNT=0")
            print("PACKAGED_XPC_SELF_TEST_OK: Vault read metadata + outline projections + JSON nested exact numbers/UTF16/paths + JS special tree/BOM positions + YAML + static JS regressions")
            return 0
        } catch {
            print("PACKAGED_XPC_SELF_TEST_FAILED: \(error)")
            return 1
        }
    }
}
