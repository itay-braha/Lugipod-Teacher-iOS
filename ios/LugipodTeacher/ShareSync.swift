import Foundation

/// Keeps the Share Extension's scoped token (see ShareBridge) in the shared app-group container:
/// minted after sign-in, renewed monthly, revoked on sign-out.
enum ShareSync {
    static func renewIfNeeded() async {
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        guard ShareBridge.needsRenewal else { return }
        struct Reply: Decodable { let token: String }
        guard let data = try? await API.post("/api/native/share/token", json: [:]),
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return }
        ShareBridge.token = reply.token
    }

    /// Sign-out: revoke on the server while the session is still valid, then forget locally.
    static func revokeAndClear() async {
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        _ = try? await API.request("DELETE", "/api/native/share/token")
        ShareBridge.clear()
    }
}
