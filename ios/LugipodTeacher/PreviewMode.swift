import Foundation

/// A development aid: `LUGIPOD_PREVIEW=<screen>` (an environment variable, set by CI through
/// `simctl launch` or by a UI test) makes a DEBUG build skip sign-in and show a screen with sample
/// data, so every screen can be screenshotted and tested in the simulator without a server.
/// Screens: login, login-code, login-email, home, availability, availability-empty, alerts, more.
/// Release builds (TestFlight) compile this away: `isOn` is always false there.
enum PreviewMode {
    #if DEBUG
    static let screen: String? = ProcessInfo.processInfo.environment["LUGIPOD_PREVIEW"]
    static var isOn: Bool { screen != nil }
    static var wantsLandscape: Bool { ProcessInfo.processInfo.environment["LUGIPOD_ORIENT"] == "landscape" }
    static var loggedOut: Bool { screen?.hasPrefix("login") == true }

    static func tab() -> AppRouter.Tab? {
        switch screen {
        case "home": return .home
        case "availability", "availability-empty": return .availability
        case "alerts": return .alerts
        case "more": return .more
        default: return nil
        }
    }

    // MARK: Sample server responses

    static func response(method: String, path: String) -> Data {
        if method != "GET" { return Data("{\"ok\":true}".utf8) }
        let json: String
        if path.hasPrefix("/api/native/home") { json = home() }
        else if path.hasPrefix("/api/native/alerts") { json = alerts() }
        else if path.hasPrefix("/api/native/availability") { json = availability(empty: screen == "availability-empty") }
        else { json = "{}" }
        return Data(json.utf8)
    }

    private static func iso(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    private static func home() -> String {
        """
        {"teacher":{"id":"t1","name":"איתי ברכה"},
         "lessons":[
           {"id":"l1","title":"מתמטיקה · 5 יח״ל","students":3,"scheduledAt":"\(iso(-600))","durationMin":90,"phase":"live"},
           {"id":"l2","title":"מדעי המחשב · 5 יח״ל","students":2,"scheduledAt":"\(iso(26 * 3600))","durationMin":90,"phase":"upcoming"},
           {"id":"l3","title":"מתמטיקה · 4 יח״ל","students":3,"scheduledAt":"\(iso(50 * 3600))","durationMin":90,"phase":"upcoming"},
           {"id":"l4","title":"מתמטיקה · כיתה י׳","students":1,"scheduledAt":"\(iso(74 * 3600))","durationMin":60,"phase":"upcoming"}],
         "summariesDue":[{"lessonId":"l0","title":"מתמטיקה · 5 יח״ל","scheduledAt":"\(iso(-30 * 3600))"}],
         "unreadAlerts":2}
        """
    }

    private static func alerts() -> String {
        """
        {"alerts":[
          {"id":"a1","type":"lesson_summary_due","title":"הגיע הזמן לסכם את השיעור","body":"שיעור מתמטיקה · 5 יח״ל הסתיים. סיכום קצר עוזר להורים ולתלמידים.","emoji":"📝","ref_id":"l0","created_at":"\(iso(-1800))","read_at":null,"path":"/lesson/l0"},
          {"id":"a2","type":"lesson_reminder","title":"השיעור מתחיל בעוד 15 דקות","body":"מתמטיקה · 5 יח״ל, 3 תלמידים.","emoji":"⏰","ref_id":"l1","created_at":"\(iso(-5400))","read_at":null,"path":"/home"},
          {"id":"a3","type":"sos_new","title":"שאלת SOS חדשה מחכה","body":"תלמיד/ה ביקש/ה הסבר דחוף באלגברה.","emoji":"🆘","ref_id":null,"created_at":"\(iso(-86400))","read_at":"\(iso(-80000))","path":"/teacher/sos"},
          {"id":"a4","type":"payout","title":"התשלום החודשי בדרך","body":null,"emoji":"💰","ref_id":null,"created_at":"\(iso(-3 * 86400))","read_at":"\(iso(-2 * 86400))","path":"/alerts"}],
         "unread":2}
        """
    }

    private static func availability(empty: Bool) -> String {
        // slot = day * 48 + halfHour; days 1, 2, 4 = Mon, Tue, Thu, 16:00-19:00 = rows 32...37.
        let rows = Array(32...37)
        let available = empty ? [] : [1, 2, 4].flatMap { d in rows.map { d * 48 + $0 } }
        let preferred = empty ? [] : [2].flatMap { d in [34, 35, 36].map { d * 48 + $0 } }
        let hot = [3 * 48 + 34, 3 * 48 + 35, 5 * 48 + 22, 0 * 48 + 38]
        let hotJSON = hot.enumerated().map { "{\"slot\":\($0.element),\"weight\":\(13 - $0.offset * 3)}" }.joined(separator: ",")
        return "{\"available\":\(available),\"preferred\":\(preferred),\"hot\":[\(hotJSON)]}"
    }
    #else
    static var isOn: Bool { false }
    #endif
}
