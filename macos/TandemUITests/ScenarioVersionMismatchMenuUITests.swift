import XCTest

/// E15-16 tdd: ui: menuBarExtra_versionMismatchScenario_menuAndBannerShowVersionError
@MainActor
final class ScenarioVersionMismatchMenuUITests: XCTestCase {
    func test_menuBarExtra_versionMismatchScenario_menuAndBannerShowVersionError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "versionMismatchMenu"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let banner = window.staticTexts["failClosedBannerMessage"]
        XCTAssertTrue(banner.waitForExistence(timeout: 2), "version-mismatch banner never appeared within 2s")
        XCTAssertEqual(
            displayText(of: banner),
            "Pixel 8 runs an incompatible Tandem version. Update both apps."
        )

        let stateLabel = window.staticTexts["menuBarStateLabel"]
        XCTAssertTrue(stateLabel.waitForExistence(timeout: 2), "menu bar state label never appeared")
        XCTAssertEqual(displayText(of: stateLabel), "Error")
    }

    private func displayText(of element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return value.isEmpty ? element.label : value
    }
}
