import Foundation
import CompareShared

struct VaultFailure: Error, LocalizedError, Sendable {
    let code: String
    let message: String
    var errorDescription: String? { "\(code)：\(message)" }
    static func invalid(_ message: String) -> Self { .init(code: "VAULT_SCOPE_INVALID", message: message) }
}

struct VaultSettings: Codable, Equatable, Sendable {
    var url = ""
    var token = ""
    var namespace = ""
    var namespacePattern = "."
    var mount = ""
    var directory = ""
    var directoryPattern = "**"
    var environment = ""
    var confirmedNonProduction = false
}

enum VaultPath {
    static func segments(_ text: String, empty: Bool = false, glob: Bool = false) throws -> [String] {
        if text.isEmpty, empty { return [] }
        guard !text.isEmpty, text.utf8.count <= 2048, !text.hasPrefix("/"), !text.hasSuffix("/"),
              !text.contains("%"), !text.contains("\\"), !text.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw VaultFailure.invalid("路径必须是相对路径，不能包含转义、控制字符或首尾斜杠。") }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 32, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && (glob || (!$0.contains("*") && !$0.contains("?"))) }) else { throw VaultFailure.invalid("路径包含空段、越级路径或不允许的通配符。") }
        return parts
    }
    static func join(_ a: String, _ b: String) -> String { [a,b].filter { !$0.isEmpty }.joined(separator: "/") }
    static func blockedProduction(_ text: String) -> Bool {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { ["prod","production","prd"].contains(String($0)) }
    }
}

struct VaultGlob: Sendable {
    let parts: [String]
    init(_ pattern: String) throws {
        parts = try VaultPath.segments(pattern, glob: true)
        guard parts.allSatisfy({ !$0.contains("**") || $0 == "**" }) else { throw VaultFailure.invalid("** 必须独占一个路径段；* 匹配一层，** 匹配任意层。") }
    }
    private func states(after path: String) -> Set<Int> {
        let words = path.isEmpty ? [] : path.split(separator: "/").map(String.init)
        var states: Set<Int> = [0]
        func close(_ input: Set<Int>) -> Set<Int> {
            var output = input
            for i in 0..<parts.count where output.contains(i) && parts[i] == "**" { output.insert(i + 1) }
            return output
        }
        states = close(states)
        for word in words {
            var next = Set<Int>()
            for i in states where i < parts.count {
                if parts[i] == "**" { next.insert(i) }
                else if segment(parts[i], word) { next.insert(i + 1) }
            }
            states = close(next)
        }
        return close(states)
    }
    func matches(_ path: String) -> Bool { states(after: path).contains(parts.count) }
    func canDescend(_ path: String) -> Bool { states(after: path).contains(where: { $0 < parts.count }) }
    private func segment(_ pattern: String, _ word: String) -> Bool {
        let p = Array(pattern), w = Array(word)
        var row = [Bool](repeating: false, count: w.count + 1); row[0] = true
        for char in p {
            var next = [Bool](repeating: false, count: w.count + 1)
            if char == "*" { next[0] = row[0] }
            for j in 1...max(1,w.count) where j <= w.count {
                next[j] = char == "*" ? row[j] || next[j - 1] : row[j - 1] && (char == "?" || char == w[j - 1])
            }
            row = next
        }
        return row[w.count]
    }
}

struct VaultLink: Sendable {
    let origin: String
    let mount: String?
    let path: String?
    let version: Int?
    let namespaceHint: String?
    func requireMatchingNamespace(_ namespace: String) throws {
        guard namespaceHint == nil || namespaceHint == namespace else {
            throw VaultFailure.invalid("网页链接的 namespace 与当前范围不同；请在高级设置拆解链接并重新读取。")
        }
    }
    static func parse(_ text: String) throws -> Self {
        guard var url = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.fragment == nil, (url.port == nil || (1...65535).contains(url.port!)) else { throw VaultFailure.invalid("请输入 Vault 服务地址或网页链接，不带账号、密码或 fragment。") }
        let encoded = url.percentEncodedPath
        let query = url.query
        let namespaceItems = url.queryItems?.filter { $0.name == "namespace" } ?? []
        guard namespaceItems.count <= 1 else { throw VaultFailure.invalid("网页链接包含重复的 namespace 参数。") }
        let namespaceHint: String?
        if let item = namespaceItems.first {
            guard let value = item.value else { throw VaultFailure.invalid("网页链接的 namespace 参数无效。") }
            let name = value.hasSuffix("/") ? String(value.dropLast()) : value
            _ = try VaultPath.segments(name, empty: true)
            namespaceHint = name
        } else { namespaceHint = nil }
        url.path = ""; url.query = nil
        guard let origin = url.string else { throw VaultFailure.invalid("地址格式错误。") }
        if encoded.isEmpty || encoded == "/" || encoded == "/ui" || encoded == "/ui/" {
            guard query == nil else { throw VaultFailure.invalid("服务地址不能包含 query。") }
            return .init(origin: origin, mount: nil, path: nil, version: nil, namespaceHint: nil)
        }
        let parts = encoded.split(separator: "/").map(String.init)
        guard parts.count >= 6, Array(parts.prefix(3)) == ["ui","vault","secrets"],
              parts[4] == "kv", let mount = parts[3].removingPercentEncoding else { throw VaultFailure.invalid("请使用服务根地址，或 /ui/vault/secrets/<mount>/kv/... 网页链接。") }
        _ = try VaultPath.segments(mount)
        let tail = parts.dropFirst(5).joined(separator: "/")
        let path: String
        if tail == "list" { path = "" }
        else { guard let decoded = tail.removingPercentEncoding else { throw VaultFailure.invalid("网页路径编码错误。") }; path = decoded }
        _ = try VaultPath.segments(path, empty: true)
        return .init(origin: origin, mount: mount, path: path, version: 2, namespaceHint: namespaceHint)
    }
}

struct VaultTarget: Sendable, Equatable {
    let origin: String
    let token: String
    let namespace: String
    let namespacePattern: String
    let mount: String
    let directory: String
    let directoryPattern: String
    let environment: String
    init(_ settings: VaultSettings) throws {
        let link = try VaultLink.parse(settings.url)
        try link.requireMatchingNamespace(settings.namespace)
        guard !VaultPath.blockedProduction(link.origin), !VaultPath.blockedProduction(link.mount ?? ""), !VaultPath.blockedProduction(link.path ?? ""), !VaultPath.blockedProduction(settings.namespace), !VaultPath.blockedProduction(settings.environment), !VaultPath.blockedProduction(settings.mount), !VaultPath.blockedProduction(settings.directory), !VaultPath.blockedProduction(settings.directoryPattern) else { throw VaultFailure.invalid("生产标识被阻止；仅允许非生产来源。") }
        guard !settings.token.isEmpty, settings.token.utf8.count <= 8192,
              settings.token.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else { throw VaultFailure.invalid("Token 必须非空且不包含空白或控制字符。") }
        _ = try VaultPath.segments(settings.namespace, empty: true)
        if settings.namespacePattern != "." { _ = try VaultGlob(settings.namespacePattern) }
        _ = try VaultPath.segments(settings.mount)
        _ = try VaultPath.segments(settings.directory, empty: true)
        if settings.directoryPattern != "." { _ = try VaultGlob(settings.directoryPattern) }
        let environmentParts = try VaultPath.segments(settings.environment)
        guard environmentParts.count == 1 else { throw VaultFailure.invalid("配置名称必须是一个可编辑的末级名称，例如 uat-swim；目录另填。") }
        origin = link.origin; token = settings.token; namespace = settings.namespace; namespacePattern = settings.namespacePattern
        mount = settings.mount; directory = settings.directory; directoryPattern = settings.directoryPattern; environment = settings.environment
    }
}

struct VaultSecret: Codable, Hashable, Sendable {
    let namespace: String
    let namespaceKey: String
    let path: String
    let directoryKey: String
    let kvVersion: Int
    var label: String { "\(namespace.isEmpty ? "root" : namespace) · \(path)" }
}
struct VaultPlan: Sendable {
    let target: VaultTarget
    let secrets: [VaultSecret]
    let discoveredNamespaces: [String]
    let created: Date
}
struct VaultCaptured: Sendable {
    let plan: VaultPlan
    let entries: [[String:String]]
    let started: Date
    let finished: Date
    let observations: [VaultObservation]
}

struct VaultObservation: Codable, Equatable, Sendable {
    let namespace: String
    let namespaceKey: String
    let path: String
    let directoryKey: String
    let kvVersion: Int
    let started: String
    let finished: String
    let metadata: VaultReadMetadata
    init(secret: VaultSecret, started: String, finished: String, metadata: VaultReadMetadata) {
        namespace = secret.namespace; namespaceKey = secret.namespaceKey
        path = secret.path; directoryKey = secret.directoryKey; kvVersion = secret.kvVersion
        self.started = started; self.finished = finished; self.metadata = metadata
    }
}

// Explicit credential-free DTO: never encode VaultTarget or VaultPlan.
struct VaultSourceSnapshot: Codable, Sendable {
    let side: String
    let origin: String
    let namespaceRoot: String
    let namespacePattern: String
    let mount: String
    let directoryRoot: String
    let directoryPattern: String
    let configurationName: String
    let started: String
    let finished: String
    let observations: [VaultObservation]
    init(_ captured: VaultCaptured, side: String) {
        let target = captured.plan.target
        self.side = side; origin = target.origin; namespaceRoot = target.namespace
        namespacePattern = target.namespacePattern; mount = target.mount
        directoryRoot = target.directory; directoryPattern = target.directoryPattern
        configurationName = target.environment; started = captured.started.ISO8601Format()
        finished = captured.finished.ISO8601Format(); observations = captured.observations
    }
    func observation(for row: ResultRow) -> VaultObservation? {
        guard let segments = row.segments, segments.count >= 2,
              case .key(let namespace) = segments[0], case .key(let path) = segments[1] else { return nil }
        return observations.first { Array($0.namespaceKey.utf16) == namespace && Array($0.directoryKey.utf16) == path }
    }
    static func json(_ sources: [Self]) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(sources))
    }
}
