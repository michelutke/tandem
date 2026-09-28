import XCTest

/// E21-03 tdd: ui: menuBarExtra_localNetworkDeniedScenario_showsExactExplanationText
@MainActor
final class ScenarioLocalNetworkDeniedUITests: XCTestCase {
    func test_menuBarExtra_localNetworkDeniedScenario_showsExactExplanationText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "localNetworkDenied"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let label = window.staticTexts["localNetworkDeniedExplanationLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "seeded localNetworkDenied explanation never appeared")
        // macOS exposes SwiftUI Text content as AXValue; label can be empty on headless runners.
        let value = label.value as? String ?? ""
        XCTAssertEqual(
            value.isEmpty ? label.label : value,
            "Tandem needs Local Network access so your phone can find this Mac."
        )

        let button = window.buttons["openSystemSettingsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Open System Settings button never appeared")
        let buttonTitle = button.title
        let buttonLabel = button.label
        XCTAssertTrue(
            buttonTitle == "Open System Settings" || buttonLabel == "Open System Settings",
            "expected title or label \"Open System Settings\", got title=\"\(buttonTitle)\" label=\"\(buttonLabel)\""
        )
    }
}
