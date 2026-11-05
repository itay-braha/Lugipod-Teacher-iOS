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

    private static func format(_ pattern: String, _ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = pattern
        return f.string(from: d)
    }

    /// "רביעי" (no "יום" prefix).
    static func weekday(_ d: Date) -> String {
        let full = format("EEEE", d)
        return full.hasPrefix("יום ") ? String(full.dropFirst(4)) : full
    }

    static func dayNumber(_ d: Date) -> String { format("d", d) }
    static func time(_ d: Date) -> String { format("HH:mm", d) }

    /// "יום רביעי, 5 בנובמבר"
    static func longDay(_ d: Date) -> String { format("EEEE, d בMMMM", d) }

    /// "17:30–19:00"
    static func timeRange(_ start: Date, minutes: Int) -> String {
        "\(time(start))–\(time(start.addingTimeInterval(Double(minutes) * 60)))"
    }

    /// "היום", "מחר", or the weekday and date.
    static func dayLabel(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "היום" }
        if Calendar.current.isDateInTomorrow(d) { return "מחר" }
        return format("EEEE, d בMMMM", d)
    }

    static func lessonText(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "היום · \(time.string(from: d))"
            : Calendar.current.isDateInTomorrow(d) ? "מחר · \(time.string(from: d))"
            : lesson.string(from: d)
    }

    /// "בעוד 15 דק׳", "לפני שעה", "בעוד יומיים". (The system formatter appends a stray "(1)" in Hebrew.)
    static func relative(_ d: Date, now: Date = Date()) -> String {
        let seconds = d.timeIntervalSince(now)
        let magnitude = abs(seconds)
        let minutes = Int(magnitude / 60), hours = Int(magnitude / 3600), days = Int(magnitude / 86400)
        if minutes < 1 { return "עכשיו" }
        let amount: String
        if minutes < 60 {
            amount = "\(minutes) דק׳"
        } else if hours < 24 {
            amount = hours == 1 ? "שעה" : hours == 2 ? "שעתיים" : "\(hours) שעות"
        } else {
            amount = days == 1 ? "יום" : days == 2 ? "יומיים" : "\(days) ימים"
        }
        return (seconds > 0 ? "בעוד " : "לפני ") + amount
    }
}
