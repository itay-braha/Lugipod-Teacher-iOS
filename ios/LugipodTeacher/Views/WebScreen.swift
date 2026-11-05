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
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
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
