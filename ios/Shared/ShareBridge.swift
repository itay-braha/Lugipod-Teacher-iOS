import Foundation

/// What the app and the Share Extension hand to each other through the shared app-group
/// container. The extension is a separate process that must not refresh the app's Supabase
/// session (refresh tokens rotate, a second refresher would sign the app out), so the app mints a
/// scoped "share token" that is valid only for /api/native/share/* and stores it here.
enum ShareBridge {
    static let group = "group.com.itaybraha.lugipod"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    static var token: String? {
        get { defaults?.string(forKey: "share.token") }
        set {
            defaults?.set(newValue, forKey: "share.token")
            defaults?.set(newValue == nil ? nil : Date(), forKey: "share.issuedAt")
        }
    }

    static var issuedAt: Date? { defaults?.object(forKey: "share.issuedAt") as? Date }

    /// Tokens live 90 days after last use on the server; the app renews its own copy monthly.
    static var needsRenewal: Bool {
        guard token != nil, let issued = issuedAt else { return true }
        return Date().timeIntervalSince(issued) > 30 * 24 * 3600
    }

    static func clear() { token = nil }
}
