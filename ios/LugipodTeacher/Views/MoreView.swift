import SwiftUI

/// Tools that are still the website inside the app, plus settings and sign out.
struct MoreView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: AppRouter
    @State private var pushDenied = false
    @State private var confirmSignOut = false
    @AppStorage(ShareMode.storageKey) private var shareMode = ShareMode.fast.rawValue

    private let tools: [(title: String, icon: String, path: String, color: Color)] = [
        ("הלוח המלא של המורה", "rectangle.grid.2x2.fill", "/teacher", .indigo),
        ("הכנסות וכלכלה", "shekelsign.circle.fill", "/teacher/economy", .green),
        ("כספת חומרים", "folder.fill", "/teacher/vault", .orange),
        ("הסברים דחופים (SOS)", "bolt.fill", "/teacher/sos", .red),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("כלים") {
                    ForEach(tools, id: \.path) { t in
                        Button { router.open(path: t.path) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: t.icon).foregroundStyle(.white)
                                    .frame(width: 32, height: 32).background(t.color, in: RoundedRectangle(cornerRadius: 8))
                                Text(t.title)
                                Spacer()
                                Image(systemName: "chevron.left").font(.footnote).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Picker("איכות השידור", selection: $shareMode) {
                        ForEach(ShareMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                } header: {
                    Text("שיתוף מסך")
                } footer: {
                    Text("מהיר משתמש במקודד של המכשיר כדי להקטין את ההשהיה בכתיבה. אם משהו נראה לא טוב, עברו ל״רגיל״. השינוי חל בתחילת השיתוף הבא.")
                }

                if pushDenied {
                    Section {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        } label: {
                            Label("התראות כבויות. הפעילו אותן בהגדרות כדי לקבל הודעה על שיעורים וסיכומים", systemImage: "bell.badge")
                                .font(.footnote)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) { confirmSignOut = true } label: {
                        Label("התנתקות", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("גרסה \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .navigationTitle("עוד")
            .task { pushDenied = await PushNotifications.shared.isDenied() }
            .confirmationDialog("להתנתק מהחשבון?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("התנתקות", role: .destructive) { Task { await auth.signOut() } }
            }
        }
    }
}
