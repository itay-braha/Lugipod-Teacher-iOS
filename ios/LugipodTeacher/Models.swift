import Foundation

// JSON from /api/native/* (keys are snake_case or camelCase; API.decoder handles both).

struct HomeResponse: Decodable {
    struct Teacher: Decodable { let id: String; let name: String }
    let teacher: Teacher
    let lessons: [LessonItem]
    let summariesDue: [SummaryDue]
    let unreadAlerts: Int
}

enum LessonPhase: String, Decodable { case upcoming, live, ended }

struct LessonItem: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let students: Int
    let scheduledAt: Date
    let durationMin: Int
    let phase: LessonPhase
}

struct SummaryDue: Decodable, Identifiable, Equatable {
    let lessonId: String
    let title: String
    let scheduledAt: Date
    var id: String { lessonId }
}

struct AlertsResponse: Decodable {
    let alerts: [AlertItem]
    let unread: Int
}

struct AlertItem: Decodable, Identifiable, Equatable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let emoji: String?
    let createdAt: Date
    let readAt: Date?
    let path: String
    var isUnread: Bool { readAt == nil }
}

enum HebrewDate {
    private static let lesson: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = "EEEE, d בMMMM · HH:mm"
        return f
    }()
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func lessonText(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "היום · \(time.string(from: d))"
            : Calendar.current.isDateInTomorrow(d) ? "מחר · \(time.string(from: d))"
            : lesson.string(from: d)
    }

    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
