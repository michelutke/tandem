import XCTest

/// E61-12 tdd: mirrorQuickAction_seededDeclinedScenario_showsMirroringDeclinedOnPhoneText.
@MainActor
final class MirrorQuickActionUITests: XCTestCase {
    func test_mirrorQuickAction_seededDeclinedScenario_showsMirroringDeclinedOnPhoneText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "mirrorDeclined"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let label = window.staticTexts["mirrorStatusLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "mirrorStatusLabel never appeared")
        XCTAssertEqual(label.label, "Mirroring declined on phone")
    }
}
