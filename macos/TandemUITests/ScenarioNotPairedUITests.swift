import XCTest

/// E00-26 tdd: ui: uiTestScenarioNotPaired_launch_menuShowsNotPaired
@MainActor
final class ScenarioNotPairedUITests: XCTestCase {
    func test_uiTestScenarioNotPaired_launch_menuShowsNotPaired() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "notPaired"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let label = app.staticTexts["notPairedStateLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "seeded notPaired label never appeared")
        XCTAssertEqual(label.label, "Not Paired")
    }
}
