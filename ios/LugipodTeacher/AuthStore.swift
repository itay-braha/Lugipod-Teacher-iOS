import Foundation
import Supabase
import UIKit

/// The teacher's login. The Supabase SDK refreshes the session; SessionVault keeps it on the device;
/// everything else asks this object for a token.
@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    enum State: Equatable { case loading, notConfigured, signedOut, signedIn }

    @Published private(set) var state: State = .loading
    /// Shown on the login screen after an automatic sign-out (for example, not a teacher account).
    @Published var notice: String?

    let client: SupabaseClient
    private let vault = SessionVault.shared
    private let storageKey: String
    /// Watchers of the session's token (the in-app web pages re-sync their cookie after every refresh).
    @Published private(set) var tokenGeneration = 0

    private init() {
        let key = SessionVault.storageKey(for: AppConfig.supabaseURL)
        storageKey = key
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseKey,
            options: SupabaseClientOptions(auth: .init(storage: SessionVault.shared, storageKey: key))
        )
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
        vault.onRepair = { detail in Task { await AuthTelemetry.report("vault_repair", detail) } }
        observeLifecycle()
        Task { await bootstrap() }
    }

    // MARK: Staying signed in
    //
    // Every new login costs a paid WhatsApp code, so the app is signed out ONLY when the login is really gone:
    //   - the person pressed "התנתקות" (signOut), or
    //   - Supabase rejected the session and the SDK deleted it (then the vault says `.absent`).
    // A Keychain that can't be read right now, no network, a timeout or a 401 from our API never sign anyone out. Whatever the
    // reason, when the login screen appears its reason is remembered and sent with the next code request, so we can see it.

    private func bootstrap() async {
        settle(reason: "launch")
        for await change in client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .tokenRefreshed, .userUpdated:
                if change.session != nil { state = .signedIn }
                if change.event == .tokenRefreshed { tokenGeneration += 1 }
            case .signedOut:
                // Trust the stored session, not the event: the SDK deletes it before it says signed out for real.
                if vault.presence(storageKey) == .absent { moveToSignedOut(reason: explicitSignOut ? "explicit" : "sdk_signed_out") }
            default: break
            }
        }
    }

    /// Decides signed in / signed out from what is stored. While the Keychain can't be read (the device has not been unlocked since
    /// it restarted, e.g. an app pre-launched by iOS) it waits instead of showing the login screen.
    private func settle(reason: String) {
        switch vault.presence(storageKey) {
        case .present:
            state = .signedIn
            unreadableChecks = 0
        case .absent: moveToSignedOut(reason: reason == "launch" ? "no_session_at_launch" : "no_session_\(reason)")
        case .unreadable:
            if state != .signedIn { state = .loading }
            unreadableChecks = reason == "retry" ? unreadableChecks + 1 : 0
            // Waiting is for a device that is still locked. Unlocked and still unreadable after ~30 s: show the login screen rather
            // than a loading screen forever (the next becoming-active check still brings the login back if it turns up).
            if unreadableChecks >= 15 && UIApplication.shared.isProtectedDataAvailable {
                moveToSignedOut(reason: "unreadable_timeout")
                return
            }
            if reason != "retry" { Task { await AuthTelemetry.report("session_unreadable", reason) } }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if state == .loading { vault.forgetCache(); settle(reason: "retry") }
            }
        }
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        for name in [UIApplication.protectedDataDidBecomeAvailableNotification, UIApplication.didBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recheck() }
            }
        }
    }

    /// Back in the app (or the device was unlocked): a login screen shown by mistake goes away by itself if the session is there.
    private func recheck() {
        guard state != .signedIn, state != .notConfigured, !explicitSignOut else { return }
        vault.forgetCache()
        if vault.presence(storageKey) == .present {
            Task { await AuthTelemetry.report("recovered_on_active", lastSignOutReason) }
            state = .signedIn
        } else if state == .loading {
            settle(reason: "recheck")
        }
    }

    /// A screen found no usable session (APIError.notSignedIn). Signs out only if nothing is stored; otherwise it was temporary.
    func sessionLost(_ screen: String) async {
        switch vault.presence(storageKey) {
        case .absent: moveToSignedOut(reason: "session_absent:\(screen)")
        case .present, .unreadable: await AuthTelemetry.report("loss_ignored", screen)
        }
    }

    private var explicitSignOut = false
    private var unreadableChecks = 0
    private var lastSignOutReason: String {
        get { UserDefaults.standard.string(forKey: "lugipod.lastSignOutReason") ?? "unknown" }
        set { UserDefaults.standard.set(newValue, forKey: "lugipod.lastSignOutReason") }
    }

    private func moveToSignedOut(reason: String) {
        let wasIn = state == .signedIn
        lastSignOutReason = reason
        state = .signedOut
        if wasIn && reason != "explicit" { Task { await AuthTelemetry.report("auto_signed_out", reason) } }
    }

    // MARK: Sign in

    /// Step 1: the WhatsApp code, through the site's own throttle (so the app cannot bypass it). If a login is in fact stored, no code is
    /// sent: the app simply goes in.
    func requestCode(phone: String) async throws {
        vault.forgetCache()
        if vault.presence(storageKey) == .present {
            await AuthTelemetry.report("code_skipped_session_present", lastSignOutReason)
            state = .signedIn
            return
        }
        await AuthTelemetry.report("code_requested", lastSignOutReason)
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
        explicitSignOut = false
        state = .signedIn
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
        explicitSignOut = false
        state = .signedIn
    }

    /// The person pressed "התנתקות" (or the account is not a teacher). Ends THIS device's login only: the website and other devices
    /// stay signed in (the SDK's default would end every session of the person).
    func signOut(notice: String? = nil, reason: String = "explicit") async {
        explicitSignOut = true
        await ShareSync.revokeAndClear()
        await PushNotifications.shared.willSignOut()
        try? await client.auth.signOut(scope: .local)
        try? vault.remove(key: storageKey)
        moveToSignedOut(reason: reason)
        self.notice = notice
    }

    // MARK: Tokens

    /// What a failed session read means: notSignedIn only when no session is stored any more; otherwise a temporary problem.
    private func sessionError(_ error: Error) -> Error {
        vault.presence(storageKey) == .absent ? APIError.notSignedIn : APIError.server(0, "offline")
    }

    /// After a 401 from our API: refresh the session once so the call can be retried. Throws notSignedIn only when the
    /// session is really gone, otherwise a temporary error (the stored session stays).
    func refreshAfterUnauthorized() async throws {
        guard AppConfig.isConfigured else { throw APIError.notSignedIn }
        do { _ = try await client.auth.refreshSession() } catch { throw sessionError(error) }
    }

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

/// Reports what happens to the login to /api/native/auth-event (table native_auth_events), so a sign-out is never a mystery again.
/// Works signed out; adds the Bearer token when there is one. Never throws, never blocks the UI for long.
enum AuthTelemetry {
    static let app = "teacher"

    static var installID: String {
        let key = "lugipod.installID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    static func report(_ event: String, _ detail: String? = nil) async {
        #if DEBUG
        return   // debug builds (CI, simulator, previews) never report: only real installs
        #endif
        guard AppConfig.isConfigured else { return }
        var req = URLRequest(url: API.baseURL.appendingPathComponent("api/native/auth-event"))
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await MainActor.run(body: { AuthStore.shared.client.auth.currentSession?.accessToken }) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "app": app, "event": event, "detail": detail ?? "", "install": installID,
            "build": (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}
