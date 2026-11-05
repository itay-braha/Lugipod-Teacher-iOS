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

    func testAvailabilityResponseDecodes() throws {
        let json = #"{"available":[114,115],"preferred":[114],"hot":[{"slot":120,"weight":6}]}"#.data(using: .utf8)!
        let r = try API.decoder.decode(AvailabilityResponse.self, from: json)
        XCTAssertEqual(r.available, [114, 115])
        XCTAssertEqual(r.hot, [HotSlot(slot: 120, weight: 6)])
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
