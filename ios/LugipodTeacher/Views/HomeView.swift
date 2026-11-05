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
            self.error = "לא הצלחנו לטעון. משכו למטה לניסיון חוזר."
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = HomeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if let error = model.error, model.data == nil {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
                }

                if let due = model.data?.summariesDue, !due.isEmpty {
                    Section {
                        ForEach(due) { s in
                            Button { router.open(path: "/lesson/\(s.lessonId)") } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundStyle(.white).frame(width: 34, height: 34)
                                        .background(.orange, in: RoundedRectangle(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title).font(.body.weight(.semibold))
                                        Text("נשאר למלא סיכום · \(HebrewDate.lessonText(s.scheduledAt))")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.left").font(.footnote).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: { Text("סיכומים שמחכים") }
                }

                Section {
                    if let lessons = model.data?.lessons {
                        if lessons.isEmpty {
                            ContentUnavailableView("אין שיעורים בשבוע הקרוב", systemImage: "calendar",
                                                   description: Text("שיעורים חדשים יופיעו כאן."))
                                .listRowBackground(Color.clear)
                        }
                        ForEach(lessons) { lesson in
                            LessonRow(lesson: lesson) { router.open(path: "/meeting/lesson/\(lesson.id)") }
                        }
                    } else if model.error == nil {
                        ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                    }
                } header: { Text("השיעורים הקרובים") }
            }
            .navigationTitle(model.data.map { "שלום, \($0.teacher.name)" } ?? "בית")
            .refreshable { await model.load() }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }
}

struct LessonRow: View {
    let lesson: LessonItem
    let join: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.title).font(.body.weight(.semibold))
                    Text(HebrewDate.lessonText(lesson.scheduledAt)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                chip
            }
            HStack {
                Label("\(lesson.students) תלמידים · \(lesson.durationMin) דק׳", systemImage: "person.2.fill")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if lesson.phase == .live {
                    Button(action: join) {
                        Label("הצטרפות לשיעור", systemImage: "video.fill").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var chip: some View {
        switch lesson.phase {
        case .live: Text("מתקיים עכשיו").font(.caption.weight(.bold)).foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 4).background(.green.opacity(0.15), in: Capsule())
        case .ended: Label("הסתיים", systemImage: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
        case .upcoming: EmptyView()
        }
    }
}
