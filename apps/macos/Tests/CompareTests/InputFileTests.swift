import Foundation
import Darwin
import Testing
@testable import CompareShared

@Suite struct InputFileTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func specialFilesFailWithoutWaitingForAWriter() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fifo = dir.appendingPathComponent("input.fifo")
        #expect(Darwin.mkfifo(fifo.path, S_IRUSR | S_IWUSR) == 0)
        let began = ContinuousClock.now
        #expect(throws: (any Error).self) { try InputFiles.read(fifo) }
        #expect(ContinuousClock.now - began < .seconds(1))
        #expect(throws: (any Error).self) { try InputFiles.read(dir) }
        #expect(throws: (any Error).self) { try InputFiles.read(URL(fileURLWithPath: "/dev/null")) }
        #expect(throws: (any Error).self) { try InputFiles.read(URL(string: "https://example.invalid/env.js")!) }
    }

    @Test func exactSizeUTF8AndSelectedSymlinkAreHandledWithoutChangingSource() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("input.js")
        let alias = dir.appendingPathComponent("alias.js")
        let content = "\u{FEFF}var env={中文:'值'};\r\n"
        try Data(content.utf8).write(to: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        #expect(try InputFiles.read(alias) == content)
        #expect(try Data(contentsOf: source) == Data(content.utf8))
        try Data(repeating: 0x61, count: InputFiles.maxBytes).write(to: source)
        #expect(try InputFiles.read(source).utf8.count == InputFiles.maxBytes)
        try Data(repeating: 0x61, count: InputFiles.maxBytes + 1).write(to: source)
        #expect(throws: (any Error).self) { try InputFiles.read(source) }
        try Data([0xC3, 0x28]).write(to: source)
        #expect(throws: (any Error).self) { try InputFiles.read(source) }
        try Data().write(to: source)
        #expect(try InputFiles.read(source).isEmpty)
    }

    @Test func exportDistinguishesMissingDirectoryAndExistingFileAndUsesPrivatePermissions() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appendingPathComponent("missing/report.json")
        do {
            try InputFiles.writeNew(Data("{}".utf8), to: missing, inputs: [])
            Issue.record("Export unexpectedly created a missing parent directory")
        } catch {
            let failure = error as NSError
            #expect(failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOENT))
        }
        let output = dir.appendingPathComponent("report.json")
        try InputFiles.writeNew(Data("{}".utf8), to: output, inputs: [])
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        do {
            try InputFiles.writeNew(Data("[]".utf8), to: output, inputs: [])
            Issue.record("Export unexpectedly overwrote an existing file")
        } catch {
            #expect((error as? CocoaError)?.code == .fileWriteFileExists)
        }
        #expect(try Data(contentsOf: output) == Data("{}".utf8))
    }

    @Test func writeFailureKeepsPartialOutputAndNeverDeletesAReplacement() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let partial = dir.appendingPathComponent("partial.json")
        #expect(throws: (any Error).self) {
            try InputFiles.writeNew(Data("full content".utf8), to: partial, inputs: []) { _, file in
                try file.write(contentsOf: Data("partial".utf8))
                throw CocoaError(.fileWriteOutOfSpace)
            }
        }
        #expect(try Data(contentsOf: partial) == Data("partial".utf8))
        let replaced = dir.appendingPathComponent("replaced.json")
        #expect(throws: (any Error).self) {
            try InputFiles.writeNew(Data("full content".utf8), to: replaced, inputs: []) { _, file in
                try file.write(contentsOf: Data("partial".utf8))
                try FileManager.default.removeItem(at: replaced)
                try Data("replacement owned by another operation".utf8).write(to: replaced)
                throw CocoaError(.fileWriteOutOfSpace)
            }
        }
        #expect(try Data(contentsOf: replaced) == Data("replacement owned by another operation".utf8))
    }
}
