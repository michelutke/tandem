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

        let label = window.staticTexts["notPairedStateLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "seeded notPaired label never appeared")
        // macOS exposes SwiftUI Text content as AXValue; label can be empty on headless runners.
        let value = label.value as? String ?? ""
        XCTAssertEqual(value.isEmpty ? label.label : value, "Not Paired")
    }
}
