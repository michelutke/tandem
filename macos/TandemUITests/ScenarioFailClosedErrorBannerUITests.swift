import XCTest

/// E22-07 tdd: ui: menuBarExtra_failClosedErrorScenario_bannerPersistsUntilOkTapped
@MainActor
final class ScenarioFailClosedErrorBannerUITests: XCTestCase {
    func test_menuBarExtra_failClosedErrorScenario_bannerPersistsUntilOkTapped() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "failClosedError"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let banner = window.staticTexts["failClosedBannerMessage"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "seeded fail-closed banner never appeared")
        let value = banner.value as? String ?? ""
        let displayText = value.isEmpty ? banner.label : value
        XCTAssertEqual(displayText, "Pixel 8 runs an incompatible Tandem version. Update both apps.")

        // The banner has no timer of its own (unit: errorBannerViewModel_after1hWithoutAck_bannerStillShown
        // proves this with virtual time); it stays until the session is ready again and offers the
        // next step instead of an OK button.
        XCTAssertTrue(banner.exists, "banner should still be shown")
        XCTAssertTrue(
            window.buttons["failClosedBannerUpdateButton"].waitForExistence(timeout: 10),
            "version mismatch banner should offer Check for update"
        )
        XCTAssertFalse(window.buttons["failClosedBannerOkButton"].exists, "banner must not offer OK")
    }
}
