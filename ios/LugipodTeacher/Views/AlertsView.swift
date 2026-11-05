import SwiftUI

/// The bell, natively. Tapping an alert marks it read and opens the screen it is about.
struct AlertsView: View {
    @EnvironmentObject private var inbox: InboxModel
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            Group {
                if inbox.alerts.isEmpty, inbox.loaded {
                    ContentUnavailableView("אין התראות", systemImage: "bell.slash",
                                           description: Text("כשיהיה משהו חדש, תראו אותו כאן ותקבלו הודעה."))
                } else if inbox.alerts.isEmpty {
                    if let error = inbox.error { Text(error).foregroundStyle(.secondary) } else { ProgressView() }
                } else {
                    List(inbox.alerts) { alert in
                        Button {
                            Task { await inbox.markRead([alert.id]) }
                            router.open(path: alert.path)
                        } label: { AlertRow(alert: alert) }
                            .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("התראות")
            .refreshable { await inbox.load() }
            .toolbar {
                if inbox.unread > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("סמן הכל כנקרא") { Task { await inbox.markAllRead() } }.font(.footnote)
                    }
                }
            }
        }
    }
}

struct AlertRow: View {
    let alert: AlertItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(alert.emoji ?? "🔔").font(.title2)
                .frame(width: 42, height: 42)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title).font(.body.weight(alert.isUnread ? .bold : .regular))
                if let body = alert.body, !body.isEmpty {
                    Text(body).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(HebrewDate.relative(alert.createdAt)).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if alert.isUnread { Circle().fill(Color.accentColor).frame(width: 9, height: 9).padding(.top, 6) }
        }
        .padding(.vertical, 4)
    }
}
