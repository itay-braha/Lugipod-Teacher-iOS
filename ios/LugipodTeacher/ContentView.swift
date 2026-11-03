import SwiftUI

struct ContentView: View {
    @ObservedObject var call: CallManager

    var body: some View {
        ZStack(alignment: .bottom) {
            WebShell(call: call).ignoresSafeArea(.container, edges: .bottom)
            if call.phase != .idle { CallBar(call: call).padding(.bottom, 12) }
        }
    }
}

/// Floating status + mic control while the native client is in the lesson.
struct CallBar: View {
    @ObservedObject var call: CallManager

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dot).frame(width: 10, height: 10)
            Text(label).font(.footnote.weight(.bold))
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
        .environment(\.layoutDirection, .rightToLeft)
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
