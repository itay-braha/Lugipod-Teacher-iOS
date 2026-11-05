import Foundation

struct WebTarget: Identifiable, Equatable {
    let id = UUID()
    let path: String
}

/// Where the app is: which tab, and which website page is open full screen. Push taps and
/// alert rows both go through `open(path:)` with the paths the server puts on each alert.
@MainActor
final class AppRouter: ObservableObject {
    enum Tab: Hashable { case home, availability, alerts, more }

    @Published var tab: Tab = .home
    @Published var web: WebTarget?

    init() {
        #if DEBUG
        if let preview = PreviewMode.tab() { tab = preview }
        #endif
    }

    func open(path: String) {
        switch Self.destination(for: path) {
        case .tab(let t): tab = t
        case .web(let p): web = WebTarget(path: p)
        }
    }

    enum Destination: Equatable { case tab(Tab), web(String) }

    /// `/home`, `/alerts`, `/teacher/availability` (native editor), `/lesson/<id>` (the summary lives
    /// on the teacher page), and website paths.
    static func destination(for path: String) -> Destination {
        if path == "/home" { return .tab(.home) }
        if path == "/alerts" { return .tab(.alerts) }
        if path == "/teacher/availability" { return .tab(.availability) }
        if path.hasPrefix("/lesson/") { return .web("/teacher") }
        if path.hasPrefix("/teacher") || path.hasPrefix("/meeting") { return .web(path) }
        return .tab(.alerts)
    }
}
