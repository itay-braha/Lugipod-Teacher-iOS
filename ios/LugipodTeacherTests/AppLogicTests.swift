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

final class WebLoginTests: XCTestCase {
    func testFormBodyIsPercentEncodedAndStable() {
        let body = String(data: WebLogin.formBody(["next": "/teacher/sos?x=1&y=2", "access_token": "a.b-c"]), encoding: .utf8)
        XCTAssertEqual(body, "access_token=a.b-c&next=%2Fteacher%2Fsos%3Fx%3D1%26y%3D2")
    }
}
