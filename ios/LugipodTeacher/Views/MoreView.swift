import SwiftUI

/// Share quality, the website pages that are not native, notification help and sign out.
struct MoreView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: AppRouter
    @State private var pushDenied = false
    @State private var confirmSignOut = false
    @AppStorage(ShareMode.storageKey) private var shareMode = ShareMode.fast.rawValue

    private let tools: [(title: String, icon: String, path: String, color: Color)] = [
        ("הלוח המלא של המורה", "rectangle.grid.2x2.fill", "/teacher", Theme.brand600),
        ("הכנסות וכלכלה", "shekelsign.circle.fill", "/teacher/economy", Theme.emerald600),
        ("כספת חומרים", "folder.fill", "/teacher/vault", Theme.amber500),
        ("הסברים דחופים (SOS)", "bolt.fill", "/teacher/sos", Theme.rose500),
    ]

    var body: some View {
        Scaffold(maxWidth: 760) {
            ScreenHeader(title: "עוד", subtitle: "הגדרות וכלים נוספים")

            if pushDenied { pushBanner }

            shareCard
            toolsCard
            accountCard

            VStack(spacing: 4) {
                Wordmark(size: 20)
                Text("גרסה \(version)").font(.heebo(12, 600)).foregroundStyle(Theme.slate400)
            }
            .padding(.top, 8)
        }
        .task { pushDenied = await PushNotifications.shared.isDenied() }
        .confirmationDialog("להתנתק מהחשבון?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("התנתקות", role: .destructive) { Task { await auth.signOut() } }
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(short) (\(build))"
    }

    private var pushBanner: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill").font(.system(size: 20)).foregroundStyle(Theme.amber800)
                Text("ההתראות כבויות. הפעילו אותן בהגדרות כדי לקבל הודעה על שיעורים וסיכומים.")
                    .font(.heebo(14, 700)).foregroundStyle(Theme.amber800).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.amber800)
            }
            .card(padding: 16, fill: Theme.amber50, border: Theme.amber200)
        }
        .buttonStyle(.plain)
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle("שיתוף מסך", icon: "rectangle.on.rectangle", color: Theme.brand600)
            VStack(spacing: 10) {
                ForEach(ShareMode.allCases, id: \.rawValue) { mode in
                    let selected = shareMode == mode.rawValue
                    Button { shareMode = mode.rawValue } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22)).foregroundStyle(selected ? Theme.brand600 : Theme.slate300)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title).font(.heebo(16, 800)).foregroundStyle(Theme.ink)
                                Text(mode == .fast ? "מקודד החומרה של המכשיר. מומלץ, פחות השהיה בכתיבה." : "ההגדרות של Daily, ללא שינוי.")
                                    .font(.heebo(13, 500)).foregroundStyle(Theme.slate500)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(selected ? Theme.brand50 : Theme.slate50, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? Theme.brand300 : Theme.slate200, lineWidth: selected ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("השינוי חל בתחילת השיתוף הבא.").font(.heebo(12, 600)).foregroundStyle(Theme.slate400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            cardTitle("כלים באתר", icon: "globe", color: Theme.slate600).padding(.bottom, 8)
            ForEach(Array(tools.enumerated()), id: \.offset) { index, t in
                Button { router.open(path: t.path) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: t.icon).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(t.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(t.title).font(.heebo(16, 700)).foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.slate300)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < tools.count - 1 { Divider().overlay(Theme.slate100) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }

    private var accountCard: some View {
        Button { confirmSignOut = true } label: {
            Label("התנתקות", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.heebo(16, 800)).foregroundStyle(Theme.rose600)
                .frame(maxWidth: .infinity).padding(.vertical, 4)
                .card(padding: 14, radius: 20)
        }
        .buttonStyle(.plain)
    }

    private func cardTitle(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(color)
            Text(text).font(.heebo(18, 800)).foregroundStyle(Theme.ink)
        }
    }
}
