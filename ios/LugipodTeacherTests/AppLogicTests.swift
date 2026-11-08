import XCTest
@testable import LugipodTeacher

final class PhoneTests: XCTestCase {
    func testFormatsAsTheUserTypes() {
        XCTAssertEqual(Phone.format("0"), "0")
        XCTAssertEqual(Phone.format("0501"), "050-1")
        XCTAssertEqual(Phone.format("0501234"), "050-123-4")
        XCTAssertEqual(Phone.format("0501234567"), "050-123-4567")
        XCTAssertEqual(Phone.format("050-123-4567 99"), "050-123-4567")
    }

    func testValidationAndE164() {
        XCTAssertTrue(Phone.isValid("050-123-4567"))
        XCTAssertFalse(Phone.isValid("050-123-456"))
        XCTAssertFalse(Phone.isValid("0201234567"))
        XCTAssertEqual(Phone.e164("050-123-4567"), "+972501234567")
    }

    func testPhoneBoxTakesNineDigitsStartingWithFive() {
        XCTAssertEqual(Phone.national("501234567"), "50-123-4567")
        XCTAssertEqual(Phone.national("5"), "5")
        XCTAssertEqual(Phone.national("5012"), "50-12")
        XCTAssertEqual(Phone.national(""), "")
        XCTAssertEqual(Phone.international("501234567"), "+972 50-123-4567")
        // typing: 0 and other first digits are refused, extra digits ignored
        XCTAssertEqual(Phone.national("0"), "")                                             // a typed 0 is never shown
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "0"), "0")                         // ...and not rewritten away under the keyboard
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "00"), "")
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "3"), "")
        XCTAssertEqual(Phone.sanitizeTyped(old: "0", new: "05"), "05")
        XCTAssertEqual(Phone.national("05"), "5")
        XCTAssertEqual(Phone.sanitizeTyped(old: "0501234567", new: "05012345679"), "0501234567")
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "5"), "5")
        XCTAssertEqual(Phone.sanitizeTyped(old: "50", new: "501"), "501")
        XCTAssertEqual(Phone.sanitizeTyped(old: "5012", new: "501234"), "501234")          // two keystrokes in one change are normal typing
        XCTAssertEqual(Phone.sanitizeTyped(old: "501234567", new: "5012345679"), "501234567")
        // paste / auto-fill, however it is written
        for pasted in ["0501234567", "501234567", "050-123-4567", "+972 50-123-4567", "972501234567", "00972501234567", "٠٥٠١٢٣٤٥٦٧"] {
            XCTAssertEqual(Phone.sanitizeTyped(old: "", new: pasted), "501234567", pasted)
        }
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "0412345678"), "")                 // a landline is not accepted
        XCTAssertTrue(Phone.isValid("501234567"))
        XCTAssertEqual(Phone.e164("501234567"), "+972501234567")
    }
}

final class DecodingTests: XCTestCase {
    func testHomeResponse() throws {
        let json = """
        {"teacher":{"id":"t1","name":"יובל"},
         "lessons":[{"id":"l1","title":"מתמטיקה · 5 יח״ל","students":3,"scheduledAt":"2026-11-04T09:19:00+00:00","durationMin":90,"phase":"live"}],
         "summariesDue":[{"lessonId":"l0","title":"אנגלית","scheduledAt":"2026-11-03T15:00:00.123456+00:00"}],
         "unreadAlerts":2}
        """.data(using: .utf8)!
        let r = try API.decoder.decode(HomeResponse.self, from: json)
        XCTAssertEqual(r.teacher.name, "יובל")
        XCTAssertEqual(r.lessons.first?.phase, .live)
        XCTAssertEqual(r.summariesDue.first?.lessonId, "l0")
        XCTAssertEqual(r.unreadAlerts, 2)
    }

    func testGroupThatMeetsTwiceAWeekCarriesItsWeeklyTimes() throws {
        let json = """
        {"teacher":{"id":"t1","name":"איתי"},
         "lessons":[
           {"id":"l1","title":"מתמטיקה","students":1,"scheduledAt":"2026-11-09T15:00:00+00:00","durationMin":90,"phase":"upcoming","groupId":"g1","weekly":2,"weeklyTimes":["יום ב׳ 17:00–18:30","יום ה׳ 17:00–18:30"]},
           {"id":"l2","title":"פיזיקה","students":3,"scheduledAt":"2026-11-10T15:00:00+00:00","durationMin":90,"phase":"upcoming"}],
         "summariesDue":[],"unreadAlerts":0}
        """.data(using: .utf8)!
        let r = try API.decoder.decode(HomeResponse.self, from: json)
        XCTAssertEqual(r.lessons[0].weeklyTimes, ["יום ב׳ 17:00–18:30", "יום ה׳ 17:00–18:30"])
        XCTAssertNil(r.lessons[1].weeklyTimes)                       // a once-a-week group (or an older server) sends none
    }

    func testAlertsResponseSnakeCase() throws {
        let json = """
        {"alerts":[{"id":"a1","type":"lesson_summary_due","title":"📝","body":null,"emoji":"📝","ref_id":"l1",
                    "created_at":"2026-11-04T09:19:00+00:00","read_at":null,"path":"/lesson/l1"}],"unread":1}
        """.data(using: .utf8)!
        let r = try API.decoder.decode(AlertsResponse.self, from: json)
        XCTAssertTrue(r.alerts[0].isUnread)
        XCTAssertEqual(r.alerts[0].path, "/lesson/l1")
        XCTAssertEqual(r.unread, 1)
    }
}

@MainActor
final class RouterTests: XCTestCase {
    func testDestinations() {
        XCTAssertEqual(AppRouter.destination(for: "/home"), .tab(.home))
        XCTAssertEqual(AppRouter.destination(for: "/alerts"), .tab(.alerts))
        XCTAssertEqual(AppRouter.destination(for: "/lesson/abc"), .web("/teacher"))
        XCTAssertEqual(AppRouter.destination(for: "/teacher/sos"), .web("/teacher/sos"))
        XCTAssertEqual(AppRouter.destination(for: "/teacher/availability"), .tab(.availability))
        XCTAssertEqual(AppRouter.destination(for: "/meeting/lesson/x"), .web("/meeting/lesson/x"))
        XCTAssertEqual(AppRouter.destination(for: "/whatever"), .tab(.alerts))
    }

    func testOpenSetsTabOrWeb() {
        let r = AppRouter()
        r.open(path: "/alerts")
        XCTAssertEqual(r.tab, .alerts)
        r.open(path: "/teacher/vault")
        XCTAssertEqual(r.web?.path, "/teacher/vault")
    }
}

final class WeekTests: XCTestCase {
    func testSlotMathMatchesTheBackend() {
        XCTAssertEqual(Week.slot(day: 2, row: 18), 114)
        XCTAssertEqual(Week.day(of: 114), 2)
        XCTAssertEqual(Week.row(of: 114), 18)
        XCTAssertEqual(Week.time(row: 18), "09:00")
        XCTAssertEqual(Week.time(row: 43), "21:30")
        XCTAssertEqual(Week.label(slot: 114), "שלישי 09:00")
        XCTAssertEqual(Week.rows.count, 26)
    }

    func testHotBlockStaysInsideTheDay() {
        XCTAssertEqual(Week.block(from: 114), [114, 115, 116])
        XCTAssertEqual(Week.block(from: 47), [47])
        XCTAssertEqual(Week.matchPercent(weight: 2), 53)
        XCTAssertEqual(Week.matchPercent(weight: 100), 95)
    }
}

@MainActor
final class AvailabilityModelTests: XCTestCase {
    func testPaintingAvailableThenPreferred() {
        let m = AvailabilityModel()
        XCTAssertFalse(m.dirty)
        m.set(114, on: true)
        XCTAssertTrue(m.dirty)
        XCTAssertTrue(m.isSet(114))

        m.mode = .preferred
        m.set(115, on: true)                     // not available: locked
        XCTAssertFalse(m.preferred.contains(115))
        m.set(114, on: true)
        XCTAssertTrue(m.preferred.contains(114))

        m.mode = .available
        m.set(114, on: false)                    // closing an hour drops it from preferred too
        XCTAssertFalse(m.preferred.contains(114))
    }

    func testOpeningAHotSlotOpensTheBlockAndClearResets() {
        let m = AvailabilityModel()
        m.openHot(114)
        XCTAssertEqual(m.available, [114, 115, 116])
        m.clearCurrent()
        XCTAssertTrue(m.available.isEmpty)
    }

    func testTapFillsALessonBlockAndASecondTapClearsOneSlot() {
        let m = AvailabilityModel()
        let s = Week.slot(day: 1, row: 32)
        m.tap(s)
        XCTAssertEqual(m.available, [s, s + 1, s + 2])
        XCTAssertTrue(m.analysis().incomplete.isEmpty)

        m.tap(s + 1)                              // clear the middle one: two lone slots are not lessons
        XCTAssertEqual(m.available, [s, s + 2])
        XCTAssertEqual(m.analysis().incomplete, [s, s + 2])
    }

    func testTapAtTheEndOfTheWindowFillsBackward() {
        let m = AvailabilityModel()
        m.tap(Week.slot(day: 4, row: Week.lastRow))
        XCTAssertEqual(m.available.count, 3)
        XCTAssertTrue(m.available.contains(Week.slot(day: 4, row: Week.lastRow - 2)))
    }

    func testPreferredCanOnlyBePickedInsideAvailable() {
        let m = AvailabilityModel()
        m.tap(Week.slot(day: 2, row: 34))
        m.mode = .preferred
        m.tap(Week.slot(day: 3, row: 34))         // not available: nothing happens
        XCTAssertTrue(m.preferred.isEmpty)
        m.tap(Week.slot(day: 2, row: 34))
        XCTAssertEqual(m.preferred.count, 3)
    }

    func testAvailabilityResponseDecodes() throws {
        let json = #"{"available":[114,115],"preferred":[114],"hot":[{"slot":120,"weight":6}]}"#.data(using: .utf8)!
        let r = try API.decoder.decode(AvailabilityResponse.self, from: json)
        XCTAssertEqual(r.available, [114, 115])
        XCTAssertEqual(r.hot, [HotSlot(slot: 120, weight: 6)])
    }
}

final class DesignSystemTests: XCTestCase {
    func testHeeboLoadsAndHonoursTheWeight() {
        XCTAssertTrue(Heebo.isAvailable, "Heebo.ttf is not registered (UIAppFonts)")
        XCTAssertEqual(Heebo.uiFont(20, 800).familyName, "Heebo")
    }

    func testBrandColorsMatchTheWebsite() {
        XCTAssertEqual(UIColor(Theme.brand600).cgColor.components?.prefix(3).map { Int(($0 * 255).rounded()) }, [79, 70, 229])
    }

    func testRelativeTimeIsPlainHebrew() {
        let now = Date()
        XCTAssertEqual(HebrewDate.relative(now.addingTimeInterval(15 * 60 + 5), now: now), "בעוד 15 דק׳")
        XCTAssertEqual(HebrewDate.relative(now.addingTimeInterval(-3600 - 5), now: now), "לפני שעה")
        XCTAssertEqual(HebrewDate.relative(now.addingTimeInterval(2 * 3600 + 5), now: now), "בעוד שעתיים")
        XCTAssertEqual(HebrewDate.relative(now.addingTimeInterval(5 * 3600 + 5), now: now), "בעוד 5 שעות")
        XCTAssertEqual(HebrewDate.relative(now.addingTimeInterval(26 * 3600), now: now), "בעוד יום")
        XCTAssertEqual(HebrewDate.relative(now.addingTimeInterval(-3 * 86400 - 5), now: now), "לפני 3 ימים")
        XCTAssertEqual(HebrewDate.relative(now.addingTimeInterval(20), now: now), "עכשיו")
    }

    func testHebrewDateHelpers() {
        let d = Date(timeIntervalSince1970: 1_793_000_000)
        XCTAssertFalse(HebrewDate.weekday(d).hasPrefix("יום"))
        XCTAssertEqual(HebrewDate.timeRange(d, minutes: 90).split(separator: "–").count, 2)
    }
}

final class ShareModeTests: XCTestCase {
    func testDefaultsToFastAndFollowsTheSetting() {
        UserDefaults.standard.removeObject(forKey: ShareMode.storageKey)
        XCTAssertEqual(ShareMode.current, .fast)
        UserDefaults.standard.set("standard", forKey: ShareMode.storageKey)
        XCTAssertEqual(ShareMode.current, .standard)
        UserDefaults.standard.set("garbage", forKey: ShareMode.storageKey)
        XCTAssertEqual(ShareMode.current, .fast)
        UserDefaults.standard.removeObject(forKey: ShareMode.storageKey)
    }
}

final class WebLoginTests: XCTestCase {
    func testFormBodyIsPercentEncodedAndStable() {
        let body = String(data: WebLogin.formBody(["next": "/teacher/sos?x=1&y=2", "access_token": "a.b-c"]), encoding: .utf8)
        XCTAssertEqual(body, "access_token=a.b-c&next=%2Fteacher%2Fsos%3Fx%3D1%26y%3D2")
    }
}

final class ShareFormatTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAgoIsPlainHebrew() {
        XCTAssertEqual(ShareFormat.ago(now.addingTimeInterval(-30), now: now), "הרגע")
        XCTAssertEqual(ShareFormat.ago(now.addingTimeInterval(-12 * 60), now: now), "לפני 12 דק׳")
        XCTAssertEqual(ShareFormat.ago(now.addingTimeInterval(-65 * 60), now: now), "לפני שעה")
        XCTAssertEqual(ShareFormat.ago(now.addingTimeInterval(-3 * 3600), now: now), "לפני 3 שעות")
        XCTAssertEqual(ShareFormat.ago(now.addingTimeInterval(-30 * 3600), now: now), "אתמול")
        XCTAssertEqual(ShareFormat.ago(now.addingTimeInterval(-50 * 3600), now: now), "לפני יומיים")
        XCTAssertEqual(ShareFormat.ago(now.addingTimeInterval(-5 * 86400), now: now), "לפני 5 ימים")
    }

    func testNamesUseFirstNames() {
        XCTAssertEqual(ShareFormat.names(["נועה פודים", "דניאל כהן"]), "נועה, דניאל")
        XCTAssertEqual(ShareFormat.names([]), "ללא תלמידים")
    }

    func testTargetsDecode() throws {
        let json = """
        {"maxBytes":26214400,"targets":[{"lessonId":"l1","groupId":"g1","title":"מתמטיקה · 5 יח״ל","students":["נועה"],
         "endedAt":"2026-11-05T17:40:00.000Z","summarized":false,"fileCount":0}]}
        """.data(using: .utf8)!
        struct Reply: Decodable { let maxBytes: Int; let targets: [ShareTarget] }
        let r = try ShareAPI.decoder.decode(Reply.self, from: json)
        XCTAssertEqual(r.targets.first?.title, "מתמטיקה · 5 יח״ל")
        XCTAssertEqual(r.maxBytes, 26_214_400)
    }

    func testTokenRenewalRules() throws {
        let saved = ShareBridge.token
        defer { ShareBridge.token = saved }
        ShareBridge.clear()
        XCTAssertTrue(ShareBridge.needsRenewal)
        ShareBridge.token = "lps_test"
        // The unsigned simulator build CI uses has no keychain entitlement, so nothing can be stored there.
        try XCTSkipIf(ShareBridge.token == nil, "no keychain access in this build")
        XCTAssertFalse(ShareBridge.needsRenewal)
    }
}
