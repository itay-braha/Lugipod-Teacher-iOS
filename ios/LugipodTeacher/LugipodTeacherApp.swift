import SwiftUI

@main
struct LugipodTeacherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthStore.shared
    @StateObject private var call = CallManager()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(call)
                .environmentObject(router)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .onAppear { PushNotifications.shared.router = router }
        }
    }
}
