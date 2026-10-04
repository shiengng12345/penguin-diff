import Foundation

enum ResultPathDisplay {
    private static let vaultRootNamespace = #"$["."]"#

    static func visible(_ path: String, vault: Bool) -> String {
        guard vault, path.hasPrefix(vaultRootNamespace) else { return path }
        return "$" + String(path.dropFirst(vaultRootNamespace.count))
    }
}
