import Foundation
import Testing
import CompareShared
import CoreBridge

private func reportRequest(_ fields: [String: Any]) throws -> String {
    let text = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    let raw = CoreBridge.process(text)
    _ = try CoreResponse.decode(raw)
    return raw
}

private func reportFileRoundtrip(_ raw: String) throws -> CoreResponse {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("typed-report.json")
    try InputFiles.writeNew(Data(raw.utf8), to: target, inputs: [])
    let restored = try InputFiles.read(target)
    #expect(restored == raw)
    let permissions = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
    return try CoreResponse.decode(restored)
}

@Suite(.serialized) struct ReportRoundTripTests {
    @Test func completeTypedReportSurvivesRealFFIFileWriteReadAndSwiftDecoding() throws {
        let session = UUID().uuidString
        defer { _ = try? reportRequest(["op":"release", "session":session]) }
        let long = "REPORT_PRIVATE_CANARY_" + String(repeating: "汉😀", count: 4096)
        let quoted = String(decoding: try JSONSerialization.data(withJSONObject: long, options: [.fragmentsAllowed]), as: UTF8.self)
        let source = #"var env={negative:-0,positive:0,nan:NaN,inf:Infinity,negInf:-Infinity,big:9007199254740993n,u:undefined,n:null,s:'\ud800',unknown:missingBinding,blob:{a:[,undefined],s:'\udfff'},long:"# + quoted + "};"
        let initial = try CoreResponse.decode(reportRequest(["op":"compare", "kind":"js", "a":source,
            "b":"var env={positive:-0,u:null,onlyB:true};", "session":session]))
        let restored = try reportFileRoundtrip(reportRequest(["op":"report", "session":session, "includeValues":true]))
        #expect(restored.complete == false && restored.incompleteRanges?.isEmpty == false)
        #expect(restored.summary?.total == initial.summary?.total)
        let rows = try #require(restored.rows)
        func find(_ key: String) throws -> ResultRow {
            try #require(rows.first(where: { $0.path == "$." + key }))
        }
        for (name, kind, literal) in [("negative","Number","-0"),("positive","Number","0"),
            ("nan","Number","NaN"),("inf","Number","Infinity"),("negInf","Number","-Infinity"),
            ("big","BigInt","9007199254740993n"),("u","Undefined","undefined"),("n","Null","null")] {
            let side = try find(name).a
            #expect(side.type == kind && side.literal == literal && side.present)
        }
        #expect(try find("positive").b.literal == "-0" && find("positive").status == "VALUE_CHANGED")
        #expect(try find("u").b.type == "Null" && find("u").status == "TYPE_CHANGED")
        let missing = try find("onlyB").a
        #expect(missing.type == "Missing" && !missing.present && missing.literal == nil)
        let unknown = try find("unknown")
        #expect(unknown.status == "NOT_COMPARABLE" && unknown.a.type == "Unknown")
        #expect(unknown.a.reason == "UNRESOLVED_EXPRESSION" && unknown.b.type == "Missing")
        #expect(try find("s").a.units == [55296])
        #expect(try find("s").segments == [.key(Array("s".utf16))])
        let blob = try find("blob").a
        #expect(blob.type == "Object" && blob.complete == true)
        let items = try #require(blob.entries?.first(where: { $0.keyUnits == [97] })?.value.items)
        #expect(items.map(\.type) == ["Hole", "Undefined"])
        #expect(blob.entries?.first(where: { $0.keyUnits == [115] })?.value.units == [57343])
        let full = try find("long")
        #expect(full.a.units == Array(long.utf16) && full.a.literal?.hasSuffix("😀\"") == true)
        #expect(full.a.truncated == nil)
        let preview = try #require(initial.rows?.first(where: { $0.path == "$.long" }))
        #expect(preview.a.truncated == true && preview.a.display.count < 400)
        let detail = try CoreResponse.decode(reportRequest(["op":"details", "session":session, "id":full.id]))
        #expect(detail.row?.a.literal == full.a.literal && detail.row?.a.units == full.a.units)
    }

    @Test func exactJSONNumbersAndNestedSurrogatesSurviveReportFileRoundtrip() throws {
        let session = UUID().uuidString
        defer { _ = try? reportRequest(["op":"release", "session":session]) }
        _ = try reportRequest(["op":"compare", "kind":"json", "session":session,
            "a":#"{"blob":{"\ud800":"\udfff","numbers":[-0,9007199254740993,1e10000]}}"#, "b":"{}"])
        let restored = try reportFileRoundtrip(reportRequest(["op":"report", "session":session]))
        let row = try #require(restored.rows?.first)
        #expect(restored.complete == true && row.status == "ONLY_A")
        #expect(row.b.type == "Missing" && !row.b.present)
        let entries = try #require(row.a.entries)
        #expect(entries.first(where: { $0.keyUnits == [55296] })?.value.units == [57343])
        let numbers = try #require(entries.first(where: { $0.keyUnits == Array("numbers".utf16) })?.value.items)
        #expect(numbers.map(\.type) == ["Number", "Number", "Number"])
        #expect(numbers.map(\.literal) == ["-0", "9007199254740993", "1e10000"])
    }

    @Test func fullReportExceedsInitialPageAndFilteredRedactedFilesKeepTheirContract() throws {
        let session = UUID().uuidString
        defer { _ = try? reportRequest(["op":"release", "session":session]) }
        let object = Dictionary(uniqueKeysWithValues: (0..<240).map { (String(format:"bulk%03d",$0), "PRIVATE_\($0)") })
        let text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let initial = try CoreResponse.decode(reportRequest(["op":"compare", "kind":"json", "session":session, "a":text, "b":"{}"] ))
        #expect(initial.summary?.total == 240 && initial.rows?.count == 200)
        let full = try reportFileRoundtrip(reportRequest(["op":"report", "session":session]))
        #expect(full.rows?.count == 240 && full.rows?.last?.path == "$.bulk239")
        let filtered = try reportFileRoundtrip(reportRequest(["op":"report", "session":session,
            "filter":"ONLY_A", "search":"bulk000", "searchScope":"key"]))
        #expect(filtered.rows?.count == 1 && filtered.rows?.first?.path == "$.bulk000")
        #expect(filtered.summary?.total == 240)
        let raw = try reportRequest(["op":"report", "session":session, "includeValues":false])
        #expect(!raw.contains("PRIVATE_"))
        let redacted = try reportFileRoundtrip(raw)
        #expect(redacted.rows?.count == 240 && redacted.summary?.total == 240)
        for row in try #require(redacted.rows) {
            #expect(row.a.type == "String" && row.a.present && row.b.type == "Missing" && !row.b.present)
            for side in [row.a,row.b] {
                #expect(side.display == "<值未导出>" && side.literal == nil && side.units == nil)
                #expect(side.entries == nil && side.items == nil && side.reason == nil)
            }
        }
    }
}
