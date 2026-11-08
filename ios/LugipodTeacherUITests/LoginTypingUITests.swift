import XCTest

/// Drives the real sign-in screen (the preview "login" screen: signed out, no server needed) on the iPad simulator the way a teacher does:
/// taps the phone box, types with the keyboard, and checks (and photographs) what is on screen. Added after testers of the student app
/// reported that the digits they typed in the sign-up phone box could not be seen, and a teacher reported the same.
final class LoginTypingUITests: XCTestCase {
    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let dir = URL(fileURLWithPath: "/tmp/lugipod-ui")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LUGIPOD_PREVIEW"] = "login"
        app.launch()
        return app
    }

    func testTypedPhoneNumberIsVisibleAndFormatted() throws {
        let app = launch()
        let input = app.textFields["phone-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "the phone box is on the first screen")
        shoot("ui-1-empty")

        input.tap()
        input.typeText("501")
        let shown = app.staticTexts["phone-display"]
        XCTAssertTrue(shown.waitForExistence(timeout: 5), "typed digits are drawn on screen")
        XCTAssertEqual(shown.label, "50-1")                  // the dash appears by itself
        shoot("ui-2a-typing")
        input.typeText("234567")
        XCTAssertEqual(shown.label, "50-123-4567")
        shoot("ui-2-typed")
    }

    func testLeadingZeroAndExtraDigitsAreIgnored() throws {
        let app = launch()
        let input = app.textFields["phone-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("0501234567")                          // someone who types the 0 anyway
        let shown = app.staticTexts["phone-display"]
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        XCTAssertEqual(shown.label, "50-123-4567")
        shoot("ui-3-typed-with-zero-ignored")
        input.typeText("99")                                  // more digits than a number has change nothing
        XCTAssertEqual(shown.label, "50-123-4567")
        input.typeText(XCUIKeyboardKey.delete.rawValue)       // and backspace takes the last digit off
        XCTAssertEqual(shown.label, "50-123-456")
    }

    func testAnotherFirstDigitIsRefused() throws {
        let app = launch()
        let input = app.textFields["phone-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("3")                                   // not a mobile number: nothing appears
        XCTAssertFalse(app.staticTexts["phone-display"].waitForExistence(timeout: 2))
        input.typeText("52")
        XCTAssertEqual(app.staticTexts["phone-display"].label, "52")
    }

    func testEmailFallbackFieldsShowWhatIsTyped() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["כניסה עם אימייל במקום"].waitForExistence(timeout: 30))
        app.buttons["כניסה עם אימייל במקום"].tap()
        let email = app.textFields["email-input"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("teacher@example.com")
        XCTAssertEqual(email.value as? String, "teacher@example.com")
        shoot("ui-4-email")
    }
}
