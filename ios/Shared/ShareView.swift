import SwiftUI

/// "Share → לוגיפוד" from Notability (or any app that shares a PDF/photo): pick the lesson the file
/// belongs to (the one that finished last is already selected) and send. The same view runs in the
/// Share Extension and, in DEBUG preview mode, inside the app so CI can photograph it.
struct ShareView: View {
    @ObservedObject var model: ShareModel
    var onClose: () -> Void
    var onDone: () -> Void

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                header
                switch model.phase {
                case .loading: centered { ProgressView(); Text("טוענים את השיעורים שלך…").font(.heebo(16, 600)).foregroundStyle(Theme.slate500) }
                case .needsSignIn: signInNeeded
                case .done: success
                default: picker
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .tint(Theme.brand600)
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.slate500)
                    .frame(width: 34, height: 34)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.slate200, lineWidth: 1))
            }
            .accessibilityLabel("סגירה")
            Spacer()
            VStack(spacing: 1) {
                Wordmark(size: 22)
                Text("שליחת סיכום לשיעור").font(.heebo(13, 600)).foregroundStyle(Theme.slate500)
            }
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func centered<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 14) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
    }

    private var signInNeeded: some View {
        centered {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44, weight: .semibold)).foregroundStyle(Theme.brand500)
            Text("צריך להתחבר פעם אחת").font(.heebo(20, 800)).foregroundStyle(Theme.ink)
            Text("פתחו את האפליקציה \"לוגיפוד למורים\" והתחברו, ואז שתפו שוב את הקובץ.")
                .font(.heebo(15, 500)).foregroundStyle(Theme.slate600).multilineTextAlignment(.center)
            Button("סגירה", action: onClose).buttonStyle(SecondaryButtonStyle()).padding(.top, 6)
        }
    }

    private var success: some View {
        centered {
            ZStack {
                Circle().fill(Theme.emerald100).frame(width: 92, height: 92)
                Image(systemName: "checkmark").font(.system(size: 40, weight: .heavy)).foregroundStyle(Theme.emerald600)
            }
            Text("הקובץ נשלח, והתלמידים כבר רואים אותו").font(.heebo(22, 800)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            if let t = model.selected {
                Text(t.title).font(.heebo(16, 600)).foregroundStyle(Theme.slate600)
                Text(ShareFormat.names(t.students)).font(.heebo(14, 500)).foregroundStyle(Theme.slate500)
            }
            VStack(spacing: 6) {
                Text("נשאר לסכם את השיעור: נוכחות ודירוג התקדמות.").font(.heebo(15, 700)).foregroundStyle(Theme.amber800)
                Text("שלחנו לך התראה שפותחת את המשך הסיכום. אפשר גם בכל זמן מהאפליקציה, תחת \"סיכומים שמחכים\".")
                    .font(.heebo(14, 500)).foregroundStyle(Theme.slate600).multilineTextAlignment(.center)
            }
            .card(padding: 14, radius: 16, fill: Theme.amber50, border: Theme.amber200)
            .frame(maxWidth: 460)
            Button("סיום", action: onDone).buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 460).padding(.top, 4)
        }
    }

    private var fileChip: some View {
        HStack(spacing: 12) {
            Image(systemName: model.file.mime == "application/pdf" ? "doc.richtext.fill" : "photo.fill")
                .font(.system(size: 22)).foregroundStyle(Theme.brand600)
                .frame(width: 44, height: 44)
                .background(Theme.brand50, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.file.name).font(.heebo(15, 700)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                Text(ShareFormat.size(model.file.size)).font(.heebo(13, 500)).foregroundStyle(Theme.slate500)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12, radius: 18)
    }

    private var picker: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    fileChip
                    Text("לאיזה שיעור הקובץ?").font(.heebo(17, 800)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    if model.targets.isEmpty {
                        Text("עדיין אין שיעורים שהתקיימו בקבוצות שלך.")
                            .font(.heebo(15, 500)).foregroundStyle(Theme.slate500).padding(.vertical, 24)
                    }
                    ForEach(model.targets) { t in row(t) }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 18).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            footer
        }
    }

    private func row(_ t: ShareTarget) -> some View {
        let on = model.selectedId == t.id
        return Button { model.selectedId = t.id } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(on ? Theme.brand600 : Theme.slate300, lineWidth: 2).frame(width: 26, height: 26)
                    if on { Circle().fill(Theme.brand600).frame(width: 14, height: 14) }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(t.title).font(.heebo(17, 800)).foregroundStyle(Theme.ink)
                    Text(ShareFormat.names(t.students)).font(.heebo(14, 500)).foregroundStyle(Theme.slate600).lineLimit(2)
                    HStack(spacing: 6) {
                        Text("הסתיים \(ShareFormat.ago(t.endedAt))").font(.heebo(13, 500)).foregroundStyle(Theme.slate500)
                        if t.summarized {
                            Pill(text: "סוכם", icon: "checkmark", fg: Theme.emerald700, bg: Theme.emerald100)
                        } else {
                            Pill(text: "ממתין לסיכום", icon: "exclamationmark.circle", fg: Theme.amber800, bg: Theme.amber100)
                        }
                        if t.fileCount > 0 {
                            Pill(text: "יש קובץ", icon: "paperclip", fg: Theme.slate600, bg: Theme.slate100)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .card(padding: 14, radius: 18, fill: on ? Theme.brand50 : .white, border: on ? Theme.brand400 : Theme.slate200)
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .sending)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if case .failed(let message) = model.phase {
                Text(message).font(.heebo(14, 700)).foregroundStyle(Theme.rose600).multilineTextAlignment(.center)
            }
            Button {
                Task { await model.send() }
            } label: {
                if model.phase == .sending {
                    HStack(spacing: 8) { ProgressView().tint(.white); Text("שולחים…") }
                } else if let t = model.selected {
                    Text("שליחה ל\(t.title)")
                } else {
                    Text("בחרו שיעור")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.selected == nil || model.phase == .sending)
            .frame(maxWidth: 560)
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}
