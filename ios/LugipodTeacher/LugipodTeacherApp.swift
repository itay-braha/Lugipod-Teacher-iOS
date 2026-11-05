import SwiftUI

@main
struct LugipodTeacherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthStore.shared
    @StateObject private var call = CallManager()
    @StateObject private var router = AppRouter()

    init() { AppAppearance.configure() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(call)
                .environmentObject(router)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .preferredColorScheme(.light)
                .tint(Theme.brand600)
                .onAppear { PushNotifications.shared.router = router }
        }
    }
}
