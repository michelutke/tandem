import XCTest

/// E22-02 tdd: ui: menuBarExtra_pairedDisconnectedScenario_quickActionsDisabled
@MainActor
final class ScenarioPairedDisconnectedUITests: XCTestCase {
    func test_menuBarExtra_pairedDisconnectedScenario_quickActionsDisabled() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "pairedDisconnected"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let identifiers = [
            "sendFileMenuItem",
            "pushClipboardMenuItem",
            "findPhoneMenuItem",
            "mirrorPhoneMenuItem"
        ]

        for identifier in identifiers {
            let button = window.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(identifier) never appeared")
            XCTAssertFalse(button.isEnabled, "\(identifier) should be disabled when disconnected")
        }
    }
}
