import Foundation
import Darwin

public struct Summary: Decodable, Sendable {
    public let total: Int
    public let same: Int
    public let valueChanged: Int
    public let typeChanged: Int
    public let onlyA: Int
    public let onlyB: Int
    public let notComparable: Int
    public let differences: Int
}
public struct Side: Decodable, Sendable {
    public let type: String
    public let display: String
    public let present: Bool
    public let truncated: Bool?
    public let line: Int?
    public let column: Int?
    public let units: [UInt16]?
    public let literal: String?
    public let complete: Bool?
    public let entries: [ObjectEntry]?
    public let items: [TypedNode]?
    public let reason: String?
}
// Full container details preserve key UTF-16 units and numeric literals without
// decoding values through Foundation Double or lossy Unicode strings.
public struct TypedNode: Decodable, Sendable {
    public let type: String
    public let display: String
    public let literal: String
    public let line: Int
    public let column: Int
    public let units: [UInt16]?
    public let complete: Bool?
    public let entries: [ObjectEntry]?
    public let items: [TypedNode]?
    public let reason: String?

    private enum CodingKeys: String, CodingKey {
        case type, display, literal, line, column, units, complete, entries, items, reason
    }
    private enum EntryKeys: String, CodingKey { case keyUnits, value }
    private struct Fields {
        let type: String, display: String, literal: String
        let line: Int, column: Int
        let units: [UInt16]?
        let complete: Bool?
        let reason: String?
    }
    private struct Record {
        let fields: Fields
        let entries: [(key: [UInt16], child: Int)]?
        let items: [Int]?
    }
    private init(fields: Fields, entries: [ObjectEntry]?, items: [TypedNode]?) {
        type = fields.type; display = fields.display; literal = fields.literal
        line = fields.line; column = fields.column; units = fields.units
        complete = fields.complete; reason = fields.reason
        self.entries = entries; self.items = items
    }
    // Decode each node's scalar fields once, then assemble children in reverse
    // order. The supported 128-level wire tree must not consume 128 nested
    // synthesized Decodable call frames on the worker's small caller stack.
    public init(from decoder: any Decoder) throws {
        var decoders: [(any Decoder)?] = [decoder]
        var records: [Record] = []
        var cursor = 0
        while cursor < decoders.count {
            let values = try decoders[cursor]!.container(keyedBy: CodingKeys.self)
            let fields = Fields(
                type: try values.decode(String.self, forKey: .type),
                display: try values.decode(String.self, forKey: .display),
                literal: try values.decode(String.self, forKey: .literal),
                line: try values.decode(Int.self, forKey: .line),
                column: try values.decode(Int.self, forKey: .column),
                units: try values.decodeIfPresent([UInt16].self, forKey: .units),
                complete: try values.decodeIfPresent(Bool.self, forKey: .complete),
                reason: try values.decodeIfPresent(String.self, forKey: .reason))
            var entries: [(key: [UInt16], child: Int)]?
            if values.contains(.entries), try !values.decodeNil(forKey: .entries) {
                var container = try values.nestedUnkeyedContainer(forKey: .entries)
                entries = []
                while !container.isAtEnd {
                    let entry = try container.nestedContainer(keyedBy: EntryKeys.self)
                    let key = try entry.decode([UInt16].self, forKey: .keyUnits)
                    let child = try entry.superDecoder(forKey: .value)
                    entries!.append((key, decoders.count)); decoders.append(child)
                }
            }
            var items: [Int]?
            if values.contains(.items), try !values.decodeNil(forKey: .items) {
                var container = try values.nestedUnkeyedContainer(forKey: .items)
                items = []
                while !container.isAtEnd {
                    let child = try container.superDecoder()
                    items!.append(decoders.count); decoders.append(child)
                }
            }
            records.append(Record(fields: fields, entries: entries, items: items))
            decoders[cursor] = nil
            cursor += 1
        }
        var nodes = [TypedNode?](repeating: nil, count: records.count)
        for index in records.indices.reversed() {
            let record = records[index]
            let entries = record.entries.map { references in
                references.map { reference in
                    let value = nodes[reference.child]!
                    nodes[reference.child] = nil
                    return ObjectEntry(keyUnits: reference.key, value: value)
                }
            }
            let items = record.items.map { references in
                references.map { child in
                    let value = nodes[child]!
                    nodes[child] = nil
                    return value
                }
            }
            nodes[index] = TypedNode(fields: record.fields, entries: entries, items: items)
        }
        self = nodes[0]!
    }
}
public struct ObjectEntry: Decodable, Sendable {
    public let keyUnits: [UInt16]
    public let value: TypedNode
}
public enum PathSegment: Decodable, Hashable, Sendable {
    case key([UInt16])
    case index(Int)
    private enum CodingKeys: String, CodingKey { case keyUnits, index }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.keyUnits), !values.contains(.index) {
            self = .key(try values.decode([UInt16].self, forKey: .keyUnits))
        } else if values.contains(.index), !values.contains(.keyUnits) {
            let index = try values.decode(Int.self, forKey: .index)
            guard index >= 0 else { throw DecodingError.dataCorruptedError(forKey: .index, in: values, debugDescription: "Invalid path index") }
            self = .index(index)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Path segment must contain exactly one key or index"))
        }
    }
}
public struct ResultRow: Decodable, Identifiable, Sendable {
    public let id: Int
    public let path: String
    public let status: String
    public let a: Side
    public let b: Side
    public let segments: [PathSegment]?
}
public struct CoreError: Decodable, Error, Sendable {
    public let code: String
    public let message: String
    public let line: Int
    public let column: Int
}
public struct SourceWarning: Decodable, Sendable {
    public let code: String
    public let message: String
    public let side: String?
    public let line: Int
    public let column: Int
    public let previousLine: Int
    public let previousColumn: Int
}
public struct VaultReadMetadata: Codable, Equatable, Sendable {
    public let kvVersion: Int
    public let version: String?
    public let createdTime: String?
    public let deletionTime: String?
    public let destroyed: Bool?
    public let state: String
    private enum CodingKeys: String, CodingKey { case kvVersion, version, createdTime, deletionTime, destroyed, state }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kvVersion, forKey: .kvVersion)
        try values.encode(version, forKey: .version)
        try values.encode(createdTime, forKey: .createdTime)
        try values.encode(deletionTime, forKey: .deletionTime)
        try values.encode(destroyed, forKey: .destroyed)
        try values.encode(state, forKey: .state)
    }
}
public struct CoreResponse: Decodable, Sendable {
    public let ok: Bool
    public let session: String?
    public let roots: [String]?
    public let summary: Summary?
    public let complete: Bool?
    public let incompleteRanges: [String]?
    public let warnings: [SourceWarning]?
    public let warningCount: Int?
    public let hasMoreWarnings: Bool?
    public let rows: [ResultRow]?
    public let row: ResultRow?
    public let text: String?
    public let vaultMetadata: VaultReadMetadata?
    public let matched: Int?
    public let error: CoreError?
    public static func decode(_ value: String) throws -> Self {
        let response = try JSONDecoder().decode(Self.self, from: Data(value.utf8))
        if let error = response.error { throw error }
        guard response.ok else { throw CocoaError(.coderInvalidValue) }
        return response
    }
}

@objc(CompareWorkerProtocol)
public protocol CompareWorkerProtocol {
    func run(_ request: String, withReply reply: @escaping @Sendable (String) -> Void)
    func stop()
}

public struct RequestGeneration: Sendable {
    private var current = UUID()
    public init() {}
    public mutating func begin() -> UUID { current = UUID(); return current }
    public func accepts(_ token: UUID) -> Bool { current == token }
}

public enum InputFiles {
    public static let maxBytes = 20 * 1024 * 1024
    public static func read(_ url: URL) throws -> String {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Nonblocking open makes even a raced replacement by a FIFO safe. Inspect
        // the opened descriptor, rather than trusting cached URL metadata.
        let opened = url.withUnsafeFileSystemRepresentation { path -> (descriptor: Int32, failure: Int32) in
            guard let path else { return (-1, EINVAL) }
            var info = stat()
            guard Darwin.fstatat(AT_FDCWD, path, &info, 0) == 0 else { return (-1, errno) }
            guard (info.st_mode & S_IFMT) == S_IFREG else { return (-1, EINVAL) }
            let descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            return (descriptor, descriptor < 0 ? errno : 0)
        }
        let fd = opened.descriptor
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(opened.failure)) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var before = stat()
        guard fstat(fd, &before) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard (before.st_mode & S_IFMT) == S_IFREG else { throw CocoaError(.fileReadUnknown) }
        guard before.st_size >= 0, before.st_size <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
        let data = try file.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
        guard String(data: data, encoding: .utf8) != nil else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        // Foundation's encoding initializer consumes a UTF-8 BOM. Decode the
        // validated bytes directly so the editor preserves the original text.
        let text = String(decoding: data, as: UTF8.self)
        var after = stat(), current = stat()
        let pathStatus = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.fstatat(AT_FDCWD, path, &current, 0)
        }
        guard fstat(fd, &after) == 0, pathStatus == 0,
              unchanged(before, after), unchanged(after, current), data.count == before.st_size else {
            throw CocoaError(.fileReadUnknown)
        }
        return text
    }
    private static func unchanged(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    public static func validateExport(_ target: URL, inputs: [URL]) throws {
        let resolved = target.standardizedFileURL.resolvingSymlinksInPath()
        let targetID = try? target.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
        for input in inputs {
            let inputID = try? input.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
            if resolved == input.standardizedFileURL.resolvingSymlinksInPath() || (targetID != nil && inputID != nil && targetID! == inputID!) { throw CocoaError(.fileWriteNoPermission) }
        }
    }
    public static func writeNew(_ data: Data, to url: URL, inputs: [URL]) throws {
        try writeNew(data, to: url, inputs: inputs) { data, file in
            try file.write(contentsOf: data)
        }
    }
    // A writer seam lets failure tests exercise the real file descriptor and
    // exclusive-create path without changing disk quotas or process limits.
    static func writeNew(_ data: Data, to url: URL, inputs: [URL], writer: (Data, FileHandle) throws -> Void) throws {
        guard url.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try validateExport(url, inputs: inputs)
        // O_EXCL is atomic and refuses existing files, symlinks and hard links.
        let opened = url.withUnsafeFileSystemRepresentation { path -> (descriptor: Int32, failure: Int32) in
            guard let path else { return (-1, EINVAL) }
            let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
            return (descriptor, descriptor < 0 ? errno : 0)
        }
        let fd = opened.descriptor
        guard fd >= 0 else {
            let failure = opened.failure
            if failure == EEXIST { throw CocoaError(.fileWriteFileExists) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do { try writer(data, file); try file.synchronize(); try file.close() }
        catch {
            try? file.close()
            // A different process can replace the destination after creation.
            // Never unlink by path on failure: it may now name someone else's
            // file. Preserve it and explain the failed export to the user.
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "导出失败；新文件可能不完整，请检查后另选文件名重新导出。",
                                     NSUnderlyingErrorKey: error])
        }
    }
}
