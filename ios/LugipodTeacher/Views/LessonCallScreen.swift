import Daily
import SwiftUI

/// The lesson on the iPad: the students' video is drawn natively at the top (or on the left in
/// landscape) and the lesson's website page runs below it as the control surface (timer, files,
/// extra time, end). The app's native client is the teacher's ONLY participant in the room: the page
/// does not join the video call, so the room (and Daily's bill) counts the teacher once.
struct LessonCallScreen: View {
    let path: String
    @EnvironmentObject private var call: CallManager

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let top = geo.safeAreaInsets.top
            ZStack {
                Color(hex: 0x0B1020).ignoresSafeArea()
                if wide {
                    HStack(spacing: 0) {
                        WebScreen(path: path)
                        CallVideoPanel(call: call)
                            .frame(width: geo.size.width * 0.42)
                            .padding(.top, top)
                    }
                } else {
                    VStack(spacing: 0) {
                        CallVideoPanel(call: call)
                            .frame(height: min(geo.size.height * 0.40, 460) + top)
                            .padding(.top, top)
                        WebScreen(path: path)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// The room as the teacher sees it: every student's camera (a name tile when the camera is off),
/// a student's shared screen when there is one, and the camera switch.
struct CallVideoPanel: View {
    @ObservedObject var call: CallManager

    private struct Item: Identifiable {
        let id: String
        let tile: CallTile
        let screen: Bool
    }

    private var items: [Item] {
        call.tiles.flatMap { t -> [Item] in
            var out = [Item(id: t.id, tile: t, screen: false)]
            if t.screen != nil { out.append(Item(id: t.id + ":screen", tile: t, screen: true)) }
            return out
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x0B1020)
            content
            controls
        }
        .clipped()
    }

    @ViewBuilder private var content: some View {
        switch call.phase {
        case .live where !items.isEmpty:
            GeometryReader { geo in
                let cols = items.count <= 1 ? 1 : 2
                let rows = (items.count + cols - 1) / cols
                let gap: CGFloat = 8
                let h = max(80, (geo.size.height - gap * CGFloat(rows + 1)) / CGFloat(rows))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: cols), spacing: gap) {
                    ForEach(items) { item in
                        CallTileView(tile: item.tile, screen: item.screen).frame(height: h)
                    }
                }
                .padding(gap)
            }
        case .live:
            status(icon: "person.2.fill", text: "ממתינים שהתלמידים יצטרפו…")
        case .joining:
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("מתחבר/ת לשיחה…").font(.heebo(15, 700)).foregroundStyle(Color(hex: 0xC7D2FE))
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 28)).foregroundStyle(Theme.amber400)
                Text(message).font(.heebo(14, 700)).foregroundStyle(.white).multilineTextAlignment(.center)
                Button("ניסיון נוסף") { Task { await call.retry() } }.buttonStyle(SoftButtonStyle())
            }
            .padding(20)
        case .idle:
            status(icon: "video.slash.fill", text: "השיחה לא פעילה")
        }
    }

    private func status(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Color(hex: 0xA5B4FC))
            Text(text).font(.heebo(15, 700)).foregroundStyle(Color(hex: 0xC7D2FE))
        }
    }

    @ViewBuilder private var controls: some View {
        if call.phase == .live {
            HStack(spacing: 10) {
                Button { call.setCamera(!call.cameraOn) } label: {
                    Image(systemName: call.cameraOn ? "video.fill" : "video.slash.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(call.cameraOn ? Theme.brand700 : .white)
                        .frame(width: 38, height: 38)
                        .background(call.cameraOn ? Color.white : Color.white.opacity(0.16), in: Circle())
                }
                .accessibilityLabel(call.cameraOn ? "כיבוי מצלמה" : "הפעלת מצלמה")
            }
            .padding(12)
        }
    }
}

struct CallTileView: View {
    let tile: CallTile
    let screen: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1E2542))
            if let track = screen ? tile.screen : tile.camera {
                DailyVideoTile(track: track, fill: !screen)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text(String(tile.name.trimmingCharacters(in: .whitespaces).prefix(1)))
                    .font(.heebo(40, 800)).foregroundStyle(Color(hex: 0xA5B4FC))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 6) {
                if !screen && tile.micMuted {
                    Image(systemName: "mic.slash.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.rose500)
                }
                Text(screen ? "המסך של \(tile.name)" : tile.name)
                    .font(.heebo(12, 700)).foregroundStyle(.white).lineLimit(1)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.black.opacity(0.45), in: Capsule())
            .padding(8)
        }
    }
}

/// Daily's video view inside SwiftUI.
struct DailyVideoTile: UIViewRepresentable {
    let track: VideoTrack?
    var fill: Bool = true

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.videoScaleMode = fill ? .fill : .fit
        view.track = track
        return view
    }

    func updateUIView(_ view: VideoView, context: Context) {
        if view.track != track { view.track = track }
        view.videoScaleMode = fill ? .fill : .fit
    }
}
