import SwiftUI

/// A website page shown full screen over the app, signed in with the native session.
struct WebScreen: View {
    let path: String
    @EnvironmentObject private var call: CallManager
    @Environment(\.dismiss) private var dismiss
    @State private var request: URLRequest?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()
            if let request {
                WebShell(call: call, request: request)
            } else if failed {
                ContentUnavailableView {
                    Label("לא הצלחנו לפתוח את העמוד", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("נסו שוב") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
            VStack {
                HStack {
                    Button {
                        if path.hasPrefix("/meeting") { call.stop() }
                        dismiss()
                    } label: {
                        Label("סגירה", systemImage: "xmark")
                            .font(.heebo(14, 800)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.white, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.slate200, lineWidth: 1))
                            .shadow(color: Theme.shadowSoft2, radius: 8, y: 3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.top, 4)
                Spacer()
            }
            if call.phase != .idle { CallBar(call: call).padding(.bottom, 12) }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        do { request = try await WebLogin.request(next: path) } catch { failed = true }
    }
}
