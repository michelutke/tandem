import XCTest

/// E00-26 tdd: ui: uiTestScenarioNotPaired_launch_menuShowsNotPaired
@MainActor
final class ScenarioNotPairedUITests: XCTestCase {
    func test_uiTestScenarioNotPaired_launch_menuShowsNotPaired() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "notPaired"]
        app.launch()

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "menu bar extra status item never appeared")
        statusItem.click()

        let label = app.staticTexts["notPairedStateLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "seeded notPaired label never appeared")
        XCTAssertEqual(label.title, "Not Paired")
    }
}
