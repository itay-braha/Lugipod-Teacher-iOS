import SwiftUI

/// The bell, as a shared object: the Alerts tab shows it, the tab bar and the app icon show its count.
@MainActor
final class InboxModel: ObservableObject {
    @Published private(set) var alerts: [AlertItem] = []
    @Published private(set) var unread = 0
    @Published private(set) var loaded = false
    @Published var error: String?

    func load() async {
        do {
            let r = try await API.get("/api/native/alerts", as: AlertsResponse.self)
            alerts = r.alerts
            unread = r.unread
            error = nil
            loaded = true
            PushNotifications.shared.setBadge(r.unread)
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            self.error = "לא הצלחנו לטעון את ההתראות"
        }
    }

    func markRead(_ ids: [String]) async {
        let set = Set(ids)
        let now = Date()
        alerts = alerts.map { a in
            set.contains(a.id) && a.isUnread
                ? AlertItem(id: a.id, type: a.type, title: a.title, body: a.body, emoji: a.emoji, createdAt: a.createdAt, readAt: now, path: a.path)
                : a
        }
        unread = alerts.filter(\.isUnread).count
        PushNotifications.shared.setBadge(unread)
        _ = try? await API.post("/api/native/alerts", json: ["ids": ids])
    }

    func markAllRead() async {
        await markRead(alerts.filter(\.isUnread).map(\.id))
        _ = try? await API.post("/api/native/alerts", json: ["all": true])
    }
}

struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var inbox = InboxModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("בית", systemImage: "house.fill") }
                .tag(AppRouter.Tab.home)
            AlertsView()
                .tabItem { Label("התראות", systemImage: "bell.fill") }
                .badge(inbox.unread)
                .tag(AppRouter.Tab.alerts)
            MoreView()
                .tabItem { Label("עוד", systemImage: "ellipsis.circle.fill") }
                .tag(AppRouter.Tab.more)
        }
        .environmentObject(inbox)
        .task { await inbox.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await inbox.load() } }
        }
    }
}
