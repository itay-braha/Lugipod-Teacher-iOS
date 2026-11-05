import XCTest

/// Drives the real availability grid in the simulator (with sample data, no server): a tap must fill
/// a 90-minute lesson block, and a press-and-drag must paint several slots. This is the check that
/// the grid answers touches, which unit tests of the model cannot prove.
final class GridUITests: XCTestCase {
    private func launch() -> (app: XCUIApplication, grid: XCUIElement, available: XCUIElement) {
        let app = XCUIApplication()
        app.launchEnvironment["LUGIPOD_PREVIEW"] = "availability-empty"
        app.launch()
        let grid = app.otherElements["week-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 30), "the week grid never appeared")
        return (app, grid, app.buttons["mode-available"])
    }

    func testTapFillsALessonBlock() throws {
        let (_, grid, available) = launch()
        let before = available.label
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        let after = available.label
        XCTAssertNotEqual(before, after, "tapping a cell did nothing (still \(before))")
        XCTAssertTrue(after.contains("1.5"), "a tap should fill 3 half-hours = 1.5 hours, got: \(after)")
    }

    func testDragPaintsSeveralSlots() throws {
        let (_, grid, available) = launch()
        let before = available.label
        let from = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2))
        let to = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
        from.press(forDuration: 0.1, thenDragTo: to)
        XCTAssertNotEqual(available.label, before, "dragging painted nothing (still \(before))")
    }

    func testSecondTapOnAFilledCellClearsIt() throws {
        let (_, grid, available) = launch()
        let spot = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        spot.tap()
        let filled = available.label
        spot.tap()
        XCTAssertNotEqual(filled, available.label, "tapping a filled cell should clear it")
    }
}
