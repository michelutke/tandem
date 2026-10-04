import XCTest

/// E40-23 tdd: ui: macosProgressRow_seededFortyTwoPercent_showsPercentAndCancelInvokesFlow
@MainActor
final class TransferProgressUITests: XCTestCase {
    func test_macosProgressRow_seededFortyTwoPercent_showsPercentAndCancelInvokesFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "transferProgressSeeded"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let percent = window.staticTexts["transferPercent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 2), "transfer percent never appeared")
        XCTAssertEqual(displayText(of: percent), "42%")

        let cancel = window.buttons["transferCancel"]
        XCTAssertTrue(cancel.exists, "Cancel button missing")
        cancel.click()

        let state = window.staticTexts["transferState"]
        XCTAssertTrue(state.waitForExistence(timeout: 2), "cancel flow never ran")
        XCTAssertEqual(displayText(of: state), "Cancelled")
    }

    private func displayText(of element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return value.isEmpty ? element.label : value
    }
}
