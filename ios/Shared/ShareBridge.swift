import Foundation
import Security

/// What the app and the Share Extension hand to each other: a scoped "share token" (valid only for
/// /api/native/share/*) kept in a shared Keychain group. The extension is a separate process that
/// must not refresh the app's Supabase session (refresh tokens rotate, a second refresher would
/// sign the app out), so it never sees that session, only this token.
///
/// The Keychain group is `<TeamID>.com.itaybraha.lugipod.shared`: keychain-sharing groups carry the
/// team prefix and need no Apple developer portal setup (an App Group would, and automatic signing
/// cannot attach it to a new extension). Unsigned simulator builds (CI tests) have no entitlement,
/// so every operation falls back to the app's default keychain group there.
enum ShareBridge {
    private static let service = "com.itaybraha.lugipod.share"

    private static var accessGroup: String? {
        let v = (Bundle.main.object(forInfoDictionaryKey: "LugipodKeychainGroup") as? String) ?? ""
        return v.isEmpty || v.hasPrefix("$(") ? nil : v
    }

    private static func query(_ account: String, group: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    private static func read(_ account: String) -> String? {
        for group in [accessGroup, nil] {
            var q = query(account, group: group)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data, let value = String(data: data, encoding: .utf8) {
                return value
            }
        }
        return nil
    }

    private static func write(_ account: String, _ value: String?) {
        for group in [accessGroup, nil] { SecItemDelete(query(account, group: group) as CFDictionary) }
        guard let value, let data = value.data(using: .utf8) else { return }
        for group in [accessGroup, nil] {
            var q = query(account, group: group)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(q as CFDictionary, nil) == errSecSuccess { return }
        }
    }

    static var token: String? {
        get { read("token") }
        set {
            write("token", newValue)
            write("issuedAt", newValue == nil ? nil : String(Int(Date().timeIntervalSince1970)))
        }
    }

    static var issuedAt: Date? { read("issuedAt").flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }

    /// Tokens live 90 days after last use on the server; the app renews its own copy monthly.
    static var needsRenewal: Bool {
        guard token != nil, let issued = issuedAt else { return true }
        return Date().timeIntervalSince(issued) > 30 * 24 * 3600
    }

    static func clear() { token = nil }
}
