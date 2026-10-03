import XCTest

/// E52-06 tdd: callAlert_activeCallScenario_showsHangUpMenuItem.
@MainActor
final class CallAlertUITests: XCTestCase {
    func test_callAlert_activeCallScenario_showsHangUpMenuItem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "incomingCallActive"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let button = window.buttons["hangUpMenuItem"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "hangUpMenuItem never appeared")
    }
}
