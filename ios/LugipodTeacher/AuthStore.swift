import Foundation
import Supabase

/// The teacher's login. The Supabase SDK keeps the session in the Keychain and refreshes it;
/// everything else asks this object for a token.
@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    enum State: Equatable { case loading, notConfigured, signedOut, signedIn }

    @Published private(set) var state: State = .loading
    /// Shown on the login screen after an automatic sign-out (for example, not a teacher account).
    @Published var notice: String?

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
        #if DEBUG
        if PreviewMode.isOn {
            state = PreviewMode.loggedOut ? .signedOut : .signedIn
            return
        }
        #endif
        guard AppConfig.isConfigured else {
            state = .notConfigured
            return
        }
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        // A stored session = signed in, even if refreshing it fails right now (no network at launch). The SDK deletes the
        // session and emits .signedOut only when Supabase really rejects it.
        state = client.auth.currentSession != nil ? .signedIn : .signedOut
        for await change in client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .tokenRefreshed: if change.session != nil { state = .signedIn }
            case .signedOut: state = .signedOut
            default: break
            }
        }
    }

    // MARK: Sign in

    /// Step 1: the WhatsApp code, through the site's own throttle (so the app cannot bypass it).
    func requestCode(phone: String) async throws {
        struct Reply: Decodable { let ok: Bool; let error: String? }
        do {
            let data = try await API.request("POST", "/api/native/otp-request", json: ["phone": phone], authorized: false)
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            if !reply.ok { throw APIError.server(400, reply.error ?? "") }
        } catch APIError.server(let status, let message) where status == 429 || status == 400 {
            throw APIError.server(status, message.isEmpty ? "לא הצלחנו לשלוח קוד. נסו שוב בעוד רגע." : message)
        }
    }

    /// Step 2: Supabase checks the code and signs the device in.
    func verify(phone: String, code: String) async throws {
        notice = nil
        _ = try await client.auth.verifyOTP(phone: Phone.e164(phone), token: code, type: .sms)
    }

    enum EmailLoginError: Error { case notAllowed }

    /// Who may use the email + password door: the admin and the test / App Review accounts. Everyone else signs in with the phone and the
    /// WhatsApp code, so we always have their number. (Same rule as the website, src/shared/emailLogin.ts, and the database.)
    nonisolated static func emailLoginAllowed(_ email: String) -> Bool {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        return e.hasSuffix("@lugipod.demo") || e == "lugipod@gmail.com"
    }

    func signIn(email: String, password: String) async throws {
        guard Self.emailLoginAllowed(email) else { throw EmailLoginError.notAllowed }
        notice = nil
        _ = try await client.auth.signIn(email: email, password: password)
    }

    func signOut(notice: String? = nil) async {
        await ShareSync.revokeAndClear()
        await PushNotifications.shared.willSignOut()
        try? await client.auth.signOut()
        state = .signedOut
        self.notice = notice
    }


    // MARK: Staying signed in
    //
    // Every new login costs a paid WhatsApp code, so the app signs out ONLY when the session is really gone: the person pressed
    // "התנתקות", or the SDK deleted the stored session because Supabase rejected the refresh token. No network at launch, a
    // timeout while refreshing, or one 401 from our API never sign anyone out (they used to, on every screen).

    /// What a failed session read means: notSignedIn only when no session is stored any more; otherwise a temporary problem.
    private func sessionError(_ error: Error) -> Error {
        client.auth.currentSession == nil ? APIError.notSignedIn : APIError.server(0, "offline")
    }

    /// After a 401 from our API: refresh the session once so the call can be retried. Throws notSignedIn only when the
    /// session is really gone, otherwise a temporary error (the stored session stays).
    func refreshAfterUnauthorized() async throws {
        guard AppConfig.isConfigured else { throw APIError.notSignedIn }
        do { _ = try await client.auth.refreshSession() } catch { throw sessionError(error) }
    }

    // MARK: Tokens

    func accessToken() async throws -> String {
        guard AppConfig.isConfigured else { throw APIError.notSignedIn }
        do { return try await client.auth.session.accessToken } catch { throw sessionError(error) }
    }

    /// For signing the in-app web pages in (POST /api/native/web-login).
    func sessionTokens() async throws -> (access: String, refresh: String) {
        guard AppConfig.isConfigured else { throw APIError.notSignedIn }
        do {
            let s = try await client.auth.session
            return (s.accessToken, s.refreshToken)
        } catch { throw sessionError(error) }
    }
}
