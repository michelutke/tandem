import XCTest

/// E41-05 tdd: photoGrid_seededPartialAccess_showsLimitedBannerWithSelectMoreButton.
@MainActor
final class PhotoGridUITests: XCTestCase {
    func test_photoGrid_seededPartialAccess_showsLimitedBannerWithSelectMoreButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "photoGridPartialAccess"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let banner = window.descendants(matching: .any)["limitedAccessBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "limitedAccessBanner never appeared")
        XCTAssertTrue(window.buttons["Select more on phone"].exists, "Select more on phone button missing")
    }
}
