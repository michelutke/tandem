import XCTest

/// E12-10 tdd: ui: failClosedErrorScenario_menuOpened_showsVersionMismatchText
@MainActor
final class ScenarioFailClosedErrorUITests: XCTestCase {
    func test_failClosedErrorScenario_menuOpened_showsVersionMismatchText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "failClosedError"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let label = window.staticTexts["failClosedErrorLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "seeded failClosedError label never appeared")
        // macOS exposes SwiftUI Text content as AXValue; label can be empty on headless runners.
        let value = label.value as? String ?? ""
        let displayText = value.isEmpty ? label.label : value
        XCTAssertEqual(displayText, "Version mismatch.")
    }
}
