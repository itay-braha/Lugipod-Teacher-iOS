import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var call: CallManager
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack(alignment: .bottom) {
            switch auth.state {
            case .loading: ProgressView()
            case .notConfigured: SetupMissingView()
            case .signedOut: LoginView()
            case .signedIn: MainTabView()
            }
            if call.phase != .idle, router.web == nil { CallBar(call: call).padding(.bottom, 64) }
        }
        .fullScreenCover(item: $router.web) { target in
            WebScreen(path: target.path)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .task(id: auth.state) {
            guard auth.state == .signedIn else { return }
            await PushNotifications.shared.requestAuthorizationAndRegister()
            await PushNotifications.shared.uploadIfPossible()
        }
    }
}

struct SetupMissingView: View {
    var body: some View {
        ContentUnavailableView(
            "האפליקציה לא הוגדרה",
            systemImage: "wrench.and.screwdriver",
            description: Text("חסרים פרטי החיבור לשרת (Secrets.xcconfig). ראו את ה-README.")
        )
    }
}

/// Floating status + mic control while the native client is in the lesson.
struct CallBar: View {
    @ObservedObject var call: CallManager

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dot).frame(width: 10, height: 10)
            Text(label).font(.footnote.weight(.bold))
            if call.sharing, let stats = call.shareStats {
                Text(stats).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if call.phase == .live {
                Button { call.setMic(!call.micOn) } label: {
                    Image(systemName: call.micOn ? "mic.fill" : "mic.slash.fill")
                        .foregroundStyle(call.micOn ? Color.primary : Color.red)
                }
                .accessibilityLabel(call.micOn ? "השתקה" : "ביטול השתקה")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6, y: 2)
    }

    private var dot: Color {
        switch call.phase {
        case .live: return call.sharing ? .red : .green
        case .joining: return .orange
        default: return .gray
        }
    }

    private var label: String {
        switch call.phase {
        case .joining: return "מתחבר/ת לשיחה…"
        case .live: return call.sharing ? "משתף/ת מסך" : "בשיחה"
        case .failed(let m): return m
        case .idle: return ""
        }
    }
}
