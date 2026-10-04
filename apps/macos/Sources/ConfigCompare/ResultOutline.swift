import Foundation
import CompareShared

// Display is readable; identity always uses original UTF-16 units and indexes.
enum OutlinePath {
    // Strip only the synthetic root; quoted keys keep their exact syntax.
    static func variableDisplay(_ path: String, rootName: String) -> String {
        if path == "$" { return rootName }
        if path.hasPrefix("$.") { return String(path.dropFirst(2)) }
        if path.hasPrefix("$[") { return String(path.dropFirst()) }
        return path
    }

    static func display(_ segments: [PathSegment]) -> String {
        segments.reduce("$") { path, segment in
            switch segment {
            case .index(let index): return path + "[\(index)]"
            case .key(let units):
                let simple = !units.isEmpty && units.allSatisfy {
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95
                }
                return path + (simple ? "." + String(decoding: units, as: UTF16.self) : "[" + quoted(units) + "]")
            }
        }
    }
    private static func quoted(_ units: [UInt16]) -> String {
        var result = "\"", index = 0
        while index < units.count {
            let unit = units[index]
            switch unit {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 10: result += "\\n"
            case 13: result += "\\r"
            case 9: result += "\\t"
            case 0xD800...0xDBFF where index + 1 < units.count && (0xDC00...0xDFFF).contains(units[index + 1]):
                let code = 0x10000 + (UInt32(unit) - 0xD800) * 0x400 + UInt32(units[index + 1]) - 0xDC00
                result.unicodeScalars.append(UnicodeScalar(code)!)
                index += 1
            case 0...31, 127...159, 0xD800...0xDFFF:
                result += String(format: "\\u%04x", unit)
            default: result.unicodeScalars.append(UnicodeScalar(UInt32(unit))!)
            }
            index += 1
        }
        return result + "\""
    }
}

enum ResultOutlineID: Hashable, Sendable {
    case branch([PathSegment])
    case result(Int)
}
struct ResultOutlineNode: Identifiable, Sendable {
    let id: ResultOutlineID
    let path: String
    let row: ResultRow?
    let children: [ResultOutlineNode]?
    let resultCount: Int
}
enum ResultOutline {
    // The input is a page of real rows; pure branches never become results.
    static func build(_ rows: [ResultRow]) -> [ResultOutlineNode] {
        let root = Branch(path: [])
        var fallback: [ResultOutlineNode] = []
        for row in rows {
            guard let segments = row.segments else {
                fallback.append(.init(id: .result(row.id), path: row.path, row: row, children: nil, resultCount: 1))
                continue
            }
            var parent = root
            for segment in segments { parent = parent.child(segment) }
            parent.row = row
        }
        let known = root.row == nil ? root.children.map { $0.freeze() } : [root.freeze()]
        return known + fallback
    }
    private final class Branch {
        let path: [PathSegment]
        let displayPath: String
        var row: ResultRow?
        var children: [Branch] = []
        private var indexes: [PathSegment:Int] = [:]
        init(path: [PathSegment], displayPath: String = "$") {
            self.path = path; self.displayPath = displayPath
        }
        func child(_ segment: PathSegment) -> Branch {
            if let index = indexes[segment] { return children[index] }
            let suffix = OutlinePath.display([segment]).dropFirst()
            let child = Branch(path: path + [segment], displayPath: displayPath + suffix)
            indexes[segment] = children.count
            children.append(child)
            return child
        }
        func freeze() -> ResultOutlineNode {
            // Swift concurrency threads have smaller stacks than the App's main
            // thread. Explicit postorder traversal also handles deep pages there.
            var pending: [(Branch, Bool)] = [(self, false)]
            var ready: [ObjectIdentifier:ResultOutlineNode] = [:]
            while let (branch, visited) = pending.popLast() {
                if !visited {
                    pending.append((branch, true))
                    for child in branch.children.reversed() { pending.append((child, false)) }
                    continue
                }
                let nodes = branch.children.map { ready.removeValue(forKey: ObjectIdentifier($0))! }
                ready[ObjectIdentifier(branch)] = .init(
                    id: branch.row.map { .result($0.id) } ?? .branch(branch.path),
                    path: branch.row?.path ?? branch.displayPath, row: branch.row,
                    children: nodes.isEmpty ? nil : nodes,
                    resultCount: (branch.row == nil ? 0 : 1) + nodes.reduce(0) { $0 + $1.resultCount })
            }
            return ready[ObjectIdentifier(self)]!
        }
    }
}

struct ValueOutlineNode: Identifiable, Sendable {
    let id: [PathSegment]
    let value: TypedNode
    var path: String { OutlinePath.display(id) }
    // Child arrays are made one level at a time; the original typed DTO is shared.
    var children: [ValueOutlineNode]? {
        let nodes = ValueOutline.children(entries: value.entries, items: value.items, path: id)
        return nodes.isEmpty ? nil : nodes
    }
    var preview: String {
        let scalars = Array(value.display.unicodeScalars.prefix(241))
        return String(String.UnicodeScalarView(scalars.prefix(240))) + (scalars.count > 240 ? "…" : "")
    }
}
enum ValueOutline {
    static func children(of side: Side) -> [ValueOutlineNode] {
        children(entries: side.entries, items: side.items, path: [])
    }
    fileprivate static func children(entries: [ObjectEntry]?, items: [TypedNode]?, path: [PathSegment]) -> [ValueOutlineNode] {
        if let entries { return entries.map { .init(id: path + [.key($0.keyUnits)], value: $0.value) } }
        if let items { return items.enumerated().map { .init(id: path + [.index($0.offset)], value: $0.element) } }
        return []
    }
}
