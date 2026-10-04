import Foundation
import Security
import LocalAuthentication

struct MCPVaultPair: Codable, Equatable, Sendable {
    let a: VaultSettings
    let b: VaultSettings
    let authorizedAt: Date
    let allowedA: [VaultSecret]
    let allowedB: [VaultSecret]
    func validate(first: VaultPlan, second: VaultPlan) throws {
        guard Set(first.secrets) == Set(allowedA), Set(second.secrets) == Set(allowedB) else {
            throw VaultFailure(code:"MCP_SCOPE_CHANGED",message:"匹配清单与 App 授权时不同；不会扩大读取范围。请回到 App 重新预览并授权。")
        }
    }
}

enum MCPVaultAuthorization {
    private static let service = "com.penguin.configcompare.mcp.vault"
    private static let account = "current-pair"
    private static var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account] }
    static func save(a: VaultSettings, b: VaultSettings, first: VaultPlan, second: VaultPlan) throws {
        _ = try VaultTarget(a); _ = try VaultTarget(b)
        guard first.target == (try VaultTarget(a)), second.target == (try VaultTarget(b)),
              Date().timeIntervalSince(first.created) <= 300, Date().timeIntervalSince(second.created) <= 300 else { throw VaultFailure.invalid("预览过期或设置已改变，请重新预览再授权 MCP。") }
        let data = try JSONEncoder().encode(MCPVaultPair(a:a,b:b,authorizedAt:Date(),allowedA:first.secrets,allowedB:second.secrets))
        let status = SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw failure() }
        } else if status != errSecSuccess { throw failure() }
    }
    static func load() throws -> MCPVaultPair {
        var item = query; item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        item[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary,&result) == errSecSuccess, let data = result as? Data,
              let pair = try? JSONDecoder().decode(MCPVaultPair.self,from:data) else { throw failure() }
        _ = try VaultTarget(pair.a); _ = try VaultTarget(pair.b)
        return pair
    }
    static func revoke() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure() }
    }
    private static func failure() -> VaultFailure { .init(code:"MCP_VAULT_NOT_AUTHORIZED",message:"未取得本机钥匙串授权。请在 App 中预览两侧非生产范围，再点击授权 MCP；凭证不会由 MCP 参数接收。") }
}
