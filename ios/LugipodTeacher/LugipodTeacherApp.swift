import SwiftUI

@main
struct LugipodTeacherApp: App {
    @StateObject private var call = CallManager()

    var body: some Scene {
        WindowGroup {
            ContentView(call: call)
        }
    }
}
