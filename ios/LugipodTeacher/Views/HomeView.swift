import SwiftUI

@MainActor
final class HomeModel: ObservableObject {
    @Published private(set) var data: HomeResponse?
    @Published private(set) var loading = false
    @Published var error: String?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            data = try await API.get("/api/native/home", as: HomeResponse.self)
            error = nil
        } catch APIError.notATeacher {
            await AuthStore.shared.signOut(notice: "החשבון הזה אינו חשבון מורה. האפליקציה מיועדת למורים בלבד.")
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            self.error = "לא הצלחנו לטעון את הנתונים. בדקו חיבור ונסו שוב."
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var inbox: InboxModel
    @StateObject private var model = HomeModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var detail: LessonItem?

    var body: some View {
        Scaffold {
            hero
            if let error = model.error, model.data == nil {
                EmptyState(pose: .peek, title: "משהו לא נטען", message: error, actionTitle: "נסו שוב") {
                    Task { await model.load() }
                }
            }
            if let due = model.data?.summariesDue, !due.isEmpty { summaries(due) }
            lessonsSection
        }
        .refreshable { await model.load() }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .sheet(item: $detail) { lesson in
            LessonDetailSheet(lesson: lesson) { path in
                detail = nil
                router.open(path: path)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(\.layoutDirection, .rightToLeft)
        }
    }

    // MARK: Hero

    private var firstName: String {
        model.data?.teacher.name.split(separator: " ").first.map(String.init) ?? ""
    }

    private var heroSubtitle: String {
        guard let data = model.data else { return "טוענים את השבוע שלך…" }
        let live = data.lessons.filter { $0.phase == .live }.count
        let upcoming = data.lessons.filter { $0.phase != .ended }.count
        if live > 0 { return live == 1 ? "יש שיעור שמתקיים עכשיו" : "יש \(live) שיעורים שמתקיימים עכשיו" }
        if upcoming == 0 { return "אין שיעורים בשבוע הקרוב" }
        return upcoming == 1 ? "שיעור אחד בשבוע הקרוב" : "\(upcoming) שיעורים בשבוע הקרוב"
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Theme.brand700, Theme.brand500, Theme.violet500],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(HebrewDate.longDay(Date()))
                        .font(.heebo(13, 600)).foregroundStyle(.white.opacity(0.78))
                    Text(firstName.isEmpty ? "שלום 👋" : "שלום, \(firstName) 👋")
                        .font(.heebo(30, 800)).foregroundStyle(.white)
                    Text(heroSubtitle)
                        .font(.heebo(16, 500)).foregroundStyle(.white.opacity(0.9))
                    HStack(spacing: 8) {
                        heroChip("השעות שלי", icon: "calendar.badge.clock") { router.tab = .availability }
                        heroChip(inbox.unread > 0 ? "\(inbox.unread) התראות חדשות" : "התראות", icon: "bell.fill") { router.tab = .alerts }
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
                Lugi(pose: .wave, height: 138).padding(.trailing, 2)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 0)
        }
        .frame(minHeight: 190)
        .shadow(color: Theme.brand600.opacity(0.28), radius: 18, y: 10)
    }

    private func heroChip(_ text: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.heebo(13, 700)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Summaries

    private func summaries(_ due: [SummaryDue]) -> some View {
        VStack(spacing: 10) {
            SectionTitle(text: "סיכומים שמחכים", count: due.count)
            ForEach(due) { s in
                Button { router.open(path: "/lesson/\(s.lessonId)") } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.amber800)
                            .frame(width: 46, height: 46)
                            .background(Theme.amber200, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.title).font(.heebo(17, 800)).foregroundStyle(Theme.ink)
                            Text((s.fileCount ?? 0) > 0
                                 ? "הקובץ כבר צורף · נשאר לדרג · \(HebrewDate.lessonText(s.scheduledAt))"
                                 : "נשאר למלא סיכום · \(HebrewDate.lessonText(s.scheduledAt))")
                                .font(.heebo(13, 500)).foregroundStyle(Theme.amber800)
                        }
                        Spacer(minLength: 8)
                        Text((s.fileCount ?? 0) > 0 ? "השלמה" : "מילוי").font(.heebo(14, 700)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Theme.amber500, in: Capsule())
                    }
                    .card(padding: 16, fill: Theme.amber50, border: Theme.amber200)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Lessons

    private struct DayGroup: Identifiable {
        let label: String
        let lessons: [LessonItem]
        var id: String { label }
    }

    private var groups: [DayGroup] {
        guard let lessons = model.data?.lessons else { return [] }
        var order: [String] = []
        var byDay: [String: [LessonItem]] = [:]
        for l in lessons {
            let label = HebrewDate.dayLabel(l.scheduledAt)
            if byDay[label] == nil { order.append(label) }
            byDay[label, default: []].append(l)
        }
        return order.map { DayGroup(label: $0, lessons: byDay[$0] ?? []) }
    }

    /// For a group that meets several times a week: its next lesson that has not ended (the list is
    /// already in time order), so "which one is next" is never a guess.
    private var nextWeeklyIds: Set<String> {
        var seen = Set<String>()
        var ids = Set<String>()
        for l in model.data?.lessons ?? [] where l.phase != .ended && (l.weekly ?? 1) > 1 {
            guard let g = l.groupId, !seen.contains(g) else { continue }
            seen.insert(g)
            ids.insert(l.id)
        }
        return ids
    }

    @ViewBuilder private var lessonsSection: some View {
        if let lessons = model.data?.lessons {
            if lessons.isEmpty {
                EmptyState(pose: .sit, title: "אין שיעורים בשבוע הקרוב",
                           message: "שיעורים חדשים יופיעו כאן ברגע ששובצו, ותקבלו על כך התראה.")
            } else {
                ForEach(groups) { group in
                    VStack(spacing: 10) {
                        SectionTitle(text: group.label)
                        ForEach(group.lessons) { lesson in
                            LessonCard(lesson: lesson,
                                       isNext: nextWeeklyIds.contains(lesson.id),
                                       join: { router.open(path: "/meeting/lesson/\(lesson.id)") },
                                       open: { detail = lesson })
                        }
                    }
                }
            }
        } else if model.error == nil {
            VStack(spacing: 10) {
                SectionTitle(text: "השיעורים הקרובים")
                ForEach(0..<2, id: \.self) { _ in
                    LessonCard(lesson: LessonItem(id: UUID().uuidString, title: "מתמטיקה · 5 יח״ל", students: 3,
                                                  scheduledAt: Date(), durationMin: 90, phase: .upcoming),
                               join: {}, open: {})
                        .redacted(reason: .placeholder)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

struct LessonCard: View {
    let lesson: LessonItem
    var isNext: Bool = false
    let join: () -> Void
    let open: () -> Void

    private var live: Bool { lesson.phase == .live }
    private var ended: Bool { lesson.phase == .ended }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                dateBlock
                VStack(alignment: .leading, spacing: 6) {
                    Text(lesson.title).font(.heebo(19, 800)).foregroundStyle(Theme.ink)
                    HStack(spacing: 14) {
                        Label(HebrewDate.timeRange(lesson.scheduledAt, minutes: lesson.durationMin), systemImage: "clock")
                        Label("\(lesson.students) תלמידים", systemImage: "person.2.fill")
                        if let w = lesson.weekly, w > 1, (lesson.weeklyTimes ?? []).isEmpty {
                            Label("\(w) מפגשים בשבוע", systemImage: "repeat")      // an older server: only the count
                        }
                    }
                    .font(.heebo(14, 600)).foregroundStyle(Theme.slate500)
                    .labelStyle(.titleAndIcon)
                    if let times = lesson.weeklyTimes, times.count > 1 {
                        Label(times.joined(separator: " · "), systemImage: "repeat")
                            .font(.heebo(13, 700)).foregroundStyle(Theme.brand700)
                            .labelStyle(.titleAndIcon)
                    }
                }
                Spacer(minLength: 8)
                status
            }
            if live {
                Button(action: join) {
                    Label("הצטרפות לשיעור", systemImage: "video.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card(padding: 18, border: live ? Theme.emerald200 : Theme.slate200)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
    }

    private var dateBlock: some View {
        VStack(spacing: 0) {
            Text(HebrewDate.weekday(lesson.scheduledAt)).font(.heebo(12, 700))
            Text(HebrewDate.dayNumber(lesson.scheduledAt)).font(.heebo(26, 900))
        }
        .foregroundStyle(live ? Theme.emerald700 : ended ? Theme.slate500 : Theme.brand700)
        .frame(width: 66, height: 70)
        .background(live ? Theme.emerald50 : ended ? Theme.slate100 : Theme.brand50,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var status: some View {
        if live {
            HStack(spacing: 6) {
                Circle().fill(Theme.emerald500).frame(width: 8, height: 8)
                Text("מתקיים עכשיו").font(.heebo(13, 800))
            }
            .foregroundStyle(Theme.emerald700)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.emerald100, in: Capsule())
        } else if ended {
            Label("הסתיים", systemImage: "checkmark.circle.fill")
                .font(.heebo(13, 700)).foregroundStyle(Theme.slate500)
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                if isNext { Pill(text: "הבא", icon: "arrow.right.circle.fill", fg: Theme.amber800, bg: Theme.amber100) }
                Pill(text: HebrewDate.relative(lesson.scheduledAt))
            }
        }
    }
}

/// What a lesson card opens: the details, and the one action that makes sense for its phase.
struct LessonDetailSheet: View {
    let lesson: LessonItem
    let go: (String) -> Void

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lesson.title).font(.heebo(26, 800)).foregroundStyle(Theme.ink)
                            Text(HebrewDate.longDay(lesson.scheduledAt)).font(.heebo(15, 600)).foregroundStyle(Theme.slate500)
                        }
                        Spacer()
                        Lugi(pose: lesson.phase == .live ? .cheer : .study, height: 90)
                    }

                    VStack(spacing: 0) {
                        row("clock", "שעה", HebrewDate.timeRange(lesson.scheduledAt, minutes: lesson.durationMin))
                        Divider().overlay(Theme.slate100)
                        row("hourglass", "משך", "\(lesson.durationMin) דקות")
                        Divider().overlay(Theme.slate100)
                        row("person.2.fill", "תלמידים בקבוצה", "\(lesson.students)")
                        if let times = lesson.weeklyTimes, times.count > 1 {
                            Divider().overlay(Theme.slate100)
                            weeklyRow(times)
                        }
                    }
                    .card(padding: 6)

                    switch lesson.phase {
                    case .live:
                        Button { go("/meeting/lesson/\(lesson.id)") } label: { Label("כניסה לחדר השיעור", systemImage: "video.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                    case .upcoming:
                        VStack(spacing: 10) {
                            Button {} label: { Label("כניסה לחדר השיעור", systemImage: "video.fill") }
                                .buttonStyle(PrimaryButtonStyle()).disabled(true)
                            Text("החדר נפתח 15 דקות לפני תחילת השיעור.")
                                .font(.heebo(14, 500)).foregroundStyle(Theme.slate500)
                        }
                    case .ended:
                        Button { go("/lesson/\(lesson.id)") } label: { Label("מעבר לסיכום השיעור", systemImage: "square.and.pencil") }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(20)
            }
        }
    }

    /// A group that meets several times a week: every weekly time on its own line, the one that comes next first.
    private func weeklyRow(_ times: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "repeat").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.brand600)
                .frame(width: 34, height: 34).background(Theme.brand50, in: RoundedRectangle(cornerRadius: 10))
            Text("מפגשים קבועים בשבוע").font(.heebo(15, 600)).foregroundStyle(Theme.slate600)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(Array(times.enumerated()), id: \.offset) { i, t in
                    HStack(spacing: 6) {
                        if i == 0 { Text("הבא").font(.heebo(11, 800)).foregroundStyle(Theme.amber800)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.amber100, in: Capsule()) }
                        Text(t).font(.heebo(16, 800)).foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.brand600)
                .frame(width: 34, height: 34).background(Theme.brand50, in: RoundedRectangle(cornerRadius: 10))
            Text(title).font(.heebo(15, 600)).foregroundStyle(Theme.slate600)
            Spacer()
            Text(value).font(.heebo(16, 800)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}
