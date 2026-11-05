import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var call: CallManager
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack(alignment: .bottom) {
            switch auth.state {
            case .loading: LoadingView()
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
            #if DEBUG
            if PreviewMode.isOn {
                if PreviewMode.wantsLandscape { Self.rotateToLandscape() }
                return
            }
            #endif
            guard auth.state == .signedIn else { return }
            await PushNotifications.shared.requestAuthorizationAndRegister()
            await PushNotifications.shared.uploadIfPossible()
        }
    }

    #if DEBUG
    private static func rotateToLandscape() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft))
    }
    #endif
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 16) {
                Lugi(pose: .walk, height: 130)
                Wordmark(size: 28)
                ProgressView()
            }
        }
    }
}

struct SetupMissingView: View {
    var body: some View {
        ZStack {
            ScreenBackground()
            EmptyState(pose: .peek, title: "האפליקציה לא הוגדרה",
                       message: "חסרים פרטי החיבור לשרת (Secrets.xcconfig). ראו את ה-README.")
                .frame(maxWidth: 460).padding(20)
        }
    }
}

/// Floating status + mic control while the native client is in the lesson.
struct CallBar: View {
    @ObservedObject var call: CallManager

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dot).frame(width: 10, height: 10)
            Text(label).font(.heebo(14, 800)).foregroundStyle(Theme.ink)
            if call.sharing, let stats = call.shareStats {
                Text(stats).font(.heebo(12, 600).monospacedDigit()).foregroundStyle(Theme.slate500)
            }
            if call.phase == .live {
                Button { call.setMic(!call.micOn) } label: {
                    Image(systemName: call.micOn ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(call.micOn ? Theme.brand700 : .white)
                        .frame(width: 34, height: 34)
                        .background(call.micOn ? Theme.brand50 : Theme.rose500, in: Circle())
                }
                .accessibilityLabel(call.micOn ? "השתקה" : "ביטול השתקה")
            }
        }
        .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 8)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.slate200, lineWidth: 1))
        .shadow(color: Theme.shadowSoft2, radius: 10, y: 4)
    }

    private var dot: Color {
        switch call.phase {
        case .live: return call.sharing ? Theme.rose500 : Theme.emerald500
        case .joining: return Theme.amber500
        default: return Theme.slate400
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
