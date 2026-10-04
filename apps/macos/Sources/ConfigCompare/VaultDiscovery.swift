import Foundation

// Credentials stay in the native reader; catalog DTOs carry names only.
protocol VaultRequestSource: Sendable {
    var origin: String { get }
    var token: String { get }
    var namespace: String { get }
}
extension VaultTarget: VaultRequestSource {}

struct VaultConnection: VaultRequestSource {
    let origin: String
    let token: String
    let namespace: String
    init(_ settings: VaultSettings) throws {
        let link = try VaultLink.parse(settings.url)
        try link.requireMatchingNamespace(settings.namespace)
        guard !VaultPath.blockedProduction(link.origin), !VaultPath.blockedProduction(link.mount ?? ""), !VaultPath.blockedProduction(link.path ?? ""), !VaultPath.blockedProduction(settings.namespace) else { throw VaultFailure.invalid("生产标识被阻止；仅允许非生产来源。") }
        guard !settings.token.isEmpty, settings.token.utf8.count <= 8192,
              settings.token.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else { throw VaultFailure.invalid("Token 必须非空且不包含空白或控制字符。") }
        _ = try VaultPath.segments(settings.namespace, empty: true)
        origin = link.origin; token = settings.token; namespace = settings.namespace
    }
}
struct VaultCatalog: Sendable, Equatable {
    let namespaces: [String]
    let mounts: [String]
    let namespaceListingUnavailable: Bool
    let excludedProduction: Bool
}
struct VaultConfigurationPath: Hashable, Sendable {
    let name: String
    let directory: String
}
struct VaultContents: Sendable, Equatable {
    let paths: Set<VaultConfigurationPath>
    /// Every directory visited by discovery, including directories whose LIST
    /// response contained no configuration names. This lets the `**` picker
    /// distinguish an empty directory from a directory that was never read.
    let discoveredDirectories: Set<String>
    /// The pattern used to produce this catalog. A catalog made from a
    /// literal directory cannot prove that `**` is common to the whole mount.
    let discoveryDirectoryPattern: String
    let excludedProduction: Bool
    init(paths: Set<VaultConfigurationPath>, discoveredDirectories: Set<String>? = nil, discoveryDirectoryPattern: String = "**", excludedProduction: Bool) {
        self.paths = paths
        self.discoveredDirectories = discoveredDirectories ?? Set(paths.map(\.directory))
        self.discoveryDirectoryPattern = discoveryDirectoryPattern
        self.excludedProduction = excludedProduction
    }
    var configurations: [String] { Set(paths.map(\.name)).sorted() }
    var directories: [String] { discoveredDirectories.sorted() }
    func directories(for name: String) -> [String] {
        Set(paths.filter { $0.name == name }.map(\.directory)).sorted()
    }
    /// Return names that are valid for the selected directory scope. `**`
    /// means every discovered directory, so only the intersection is offered.
    func configurations(forDirectory directory: String) -> [String] {
        if directory == "**" {
            guard discoveryDirectoryPattern == "**" else { return [] }
            let grouped = Dictionary(grouping: paths, by: \.directory)
            // A mount-root secret is not a child directory. When child
            // directories exist, "all directories" means their shared names;
            // otherwise a root-only mount still has useful choices.
            let childDirectories = discoveredDirectories.filter { $0 != "." }
            let scope = childDirectories.isEmpty ? discoveredDirectories : childDirectories
            let scoped = scope.map { grouped[$0] ?? [] }
            guard let first = scoped.first else { return [] }
            let common = scoped.dropFirst().reduce(Set(first.map(\.name))) { names, values in
                names.intersection(values.map(\.name))
            }
            return common.sorted()
        }
        return Set(paths.filter { $0.directory == directory }.map(\.name)).sorted()
    }
    func validatedConfigurationName(_ name: String, forDirectory directory: String) -> String {
        name.isEmpty || configurations(forDirectory: directory).contains(name) ? name : ""
    }
}

extension VaultSettings {
    mutating func updateNamespace(_ value: String) {
        namespace = value
        namespacePattern = "."
        environment = ""
    }
    mutating func updateNamespacePattern(_ value: String) {
        namespacePattern = value
        environment = ""
    }
    mutating func updateMount(_ value: String) {
        mount = value
        environment = ""
        directoryPattern = "**"
    }
    mutating func updateDirectory(_ value: String) {
        directory = value
        environment = ""
    }
    mutating func updateDirectoryPattern(_ value: String, contents: VaultContents?) {
        directoryPattern = value
        if let contents {
            environment = contents.validatedConfigurationName(environment, forDirectory: value)
        }
    }
    mutating func selectConfiguration(_ value: String, contents: VaultContents) {
        environment = contents.validatedConfigurationName(value, forDirectory: directoryPattern)
    }
}
