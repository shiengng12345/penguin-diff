import Foundation
import Testing
import CompareShared
import CoreBridge

@Test func actualRustBridgePreservesTypeChanges() throws {
    let input = #"{"op":"compare","kind":"json","a":"{\"port\":3000}","b":"{\"port\":\"3000\"}","session":"swift-test","inputType":"plain-object"}"#
    let response = try CoreResponse.decode(CoreBridge.process(input))
    #expect(response.ok)
    #expect(response.summary?.typeChanged == 1)
    #expect(response.rows?.first?.a.display == "3000")
    #expect(response.rows?.first?.b.display == "\"3000\"")
}

@Test func exportCannotOverwriteAnInputThroughASymlink() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("env.js")
    let alias = directory.appendingPathComponent("report.json")
    try Data("var env={a:1};".utf8).write(to: source)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
    #expect(throws: (any Error).self) { try InputFiles.validateExport(alias, inputs: [source]) }
    #expect(try String(contentsOf: source, encoding: .utf8) == "var env={a:1};")
}

@Test func invalidJSONReportsAnErrorWithoutDroppingTheInput() {
    #expect(throws: (any Error).self) { try CoreResponse.decode(CoreBridge.process(#"{"op":"compare","kind":"json","a":"{","b":"{}","inputType":"plain-object"}"#)) }
}

@Test func staleResponseCannotReplaceNewerRequest() {
    var generation = RequestGeneration()
    let old = generation.begin()
    let current = generation.begin()
    #expect(!generation.accepts(old))
    #expect(generation.accepts(current))
}
@Test func exclusiveExportProtectsExistingFilesAndHardLinks() throws {
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:dir) }
    let source=dir.appendingPathComponent("source.yaml")
    let alias=dir.appendingPathComponent("report.yaml")
    try Data("a: 1".utf8).write(to:source)
    try FileManager.default.linkItem(at:source,to:alias)
    #expect(throws:(any Error).self){try InputFiles.writeNew(Data("replacement".utf8),to:alias,inputs:[source])}
    #expect(throws:(any Error).self){try InputFiles.writeNew(Data("replacement".utf8),to:source,inputs:[])}
    #expect(try String(contentsOf:source,encoding:.utf8)=="a: 1")
    let new=dir.appendingPathComponent("new.yaml")
    try InputFiles.writeNew(Data("a: 2".utf8),to:new,inputs:[source])
    #expect(try String(contentsOf:new,encoding:.utf8)=="a: 2")
}
