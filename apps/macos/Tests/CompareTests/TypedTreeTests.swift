import Foundation
import Testing
import CompareShared
import CoreBridge

private func coreResponse(_ fields: [String: Any]) throws -> CoreResponse {
    let request = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    return try CoreResponse.decode(CoreBridge.process(request))
}
private func child(_ entries: [ObjectEntry]?, _ name: String) throws -> TypedNode {
    try #require(entries?.first(where: { $0.keyUnits == Array(name.utf16) })?.value)
}

@Suite(.serialized) struct TypedTreeTests {
    @Test func jsonContainerDetailsKeepNestedNumbersAndUnpairedUTF16() throws {
        let session = UUID().uuidString
        let text = #"{"blob":{"\ud800":"\ud800","nested":[-0,9007199254740993,1e10000,{"\udfff":true}],"business":{"data":{"data":"keep"}}}}"#
        let compared = try coreResponse(["op":"compare", "kind":"json", "a":text, "b":"{}", "session":session])
        #expect(compared.summary?.onlyA == 1)
        let detail = try coreResponse(["op":"details", "session":session, "id":0])
        let row = try #require(detail.row)
        #expect(row.segments == [.key(Array("blob".utf16))])
        #expect(row.a.type == "Object" && row.a.complete == true)
        let surrogate = try #require(row.a.entries?.first(where: { $0.keyUnits == [55296] }))
        #expect(surrogate.value.type == "String" && surrogate.value.units == [55296])
        let items = try #require(try child(row.a.entries, "nested").items)
        #expect(items.map(\.type) == ["Number", "Number", "Number", "Object"])
        #expect(items.prefix(3).map(\.literal) == ["-0", "9007199254740993", "1e10000"])
        #expect(items[3].entries?.first?.keyUnits == [57343])
        #expect(items[3].entries?.first?.value.literal == "true")
        let data = try child(try child(row.a.entries, "business").entries, "data")
        #expect(try child(data.entries, "data").units == Array("keep".utf16))
        _ = try coreResponse(["op":"release", "session":session])
    }

    @Test func jsContainerDetailsDistinguishSpecialTypesAndArrayIndexes() throws {
        let session = UUID().uuidString
        let source = #"var env={blob:{s:'\udfff',n:-0,b:9007199254740993n,u:undefined,nan:NaN,i:Infinity,a:[,undefined]}};"#
        _ = try coreResponse(["op":"compare", "kind":"js", "a":source, "b":"var env={};", "session":session])
        let side = try #require(try coreResponse(["op":"details", "session":session, "id":0]).row?.a)
        for (name, kind, literal) in [("n","Number","-0"),("b","BigInt","9007199254740993n"),("u","Undefined","undefined"),("nan","Number","NaN"),("i","Number","Infinity")] {
            let node = try child(side.entries, name)
            #expect(node.type == kind && node.literal == literal)
        }
        #expect(try child(side.entries, "s").units == [57343])
        #expect(try child(side.entries, "a").items?.map(\.type) == ["Hole", "Undefined"])
        _ = try coreResponse(["op":"release", "session":session])
        let array = try coreResponse(["op":"compare", "kind":"json", "a":#"{"x":[1]}"#, "b":#"{"x":[2]}"#, "session":session])
        #expect(array.rows?.first?.segments == [.key([120]), .index(0)])
        _ = try coreResponse(["op":"release", "session":session])
    }

    @Test func invalidMachinePathsFailDecodingInsteadOfLosingIdentity() {
        for text in [#"{}"#, #"{"keyUnits":[1],"index":0}"#, #"{"index":-1}"#, #"{"keyUnits":[65536]}"#] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(PathSegment.self, from: Data(text.utf8)) }
        }
    }

    @Test func iterativeNodeDecoderRetainsStrictRequiredFieldsAndOptionalShapes() throws {
        let base: [String:Any] = ["type":"String", "display":"value", "literal":"value", "line":1, "column":2]
        let decode = { (fields: [String:Any]) throws in
            try JSONDecoder().decode(TypedNode.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        let absent = try decode(base)
        #expect(absent.entries == nil && absent.items == nil && absent.units == nil)
        var nulls = base
        for key in ["entries","items","units","complete","reason"] { nulls[key] = NSNull() }
        let null = try decode(nulls)
        #expect(null.entries == nil && null.items == nil && null.units == nil && null.complete == nil && null.reason == nil)
        var both = base
        both["entries"] = [["keyUnits":[55296],"value":base]]
        both["items"] = [base]
        let decoded = try decode(both)
        #expect(decoded.entries?.first?.keyUnits == [55296] && decoded.entries?.first?.value.column == 2)
        #expect(decoded.items?.first?.line == 1)
        both["entries"] = []; both["items"] = []
        #expect(try decode(both).entries?.isEmpty == true && decode(both).items?.isEmpty == true)
        for key in ["type","display","literal","line","column"] {
            var missing = base; missing.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try decode(missing) }
            var wrong = base; wrong[key] = NSNull()
            #expect(throws: (any Error).self) { try decode(wrong) }
        }
        for (key, value) in [("units", [65536] as Any), ("entries", [1]), ("items", [NSNull()]),
                             ("complete", "true"), ("reason", 1), ("line", "1"),
                             ("entries", [["keyUnits":[1]]]),
                             ("entries", [["keyUnits":[-1],"value":base]]),
                             ("items", [["type":"String"]])] {
            var malformed = base; malformed[key] = value
            #expect(throws: (any Error).self) { try decode(malformed) }
        }
    }
}
