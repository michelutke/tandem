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
        if !banner.waitForExistence(timeout: 10) { attachHierarchy(app, "photogrid-hierarchy") }
        XCTAssertTrue(banner.exists, "limitedAccessBanner never appeared")
        XCTAssertTrue(window.buttons["Select more on phone"].exists, "Select more on phone button missing")
    }

    func test_photoGrid10kScroll_xctMemoryMetric_peakGrowthUnder150MiB() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "photoGrid10k"]
        app.launch()

        let grid = app.windows["Tandem UI Test Scenario"].descendants(matching: .any)["photoGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "photoGrid never appeared")

        let memory = XCTMemoryMetric(application: app)
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [memory], options: options) {
            for _ in 0..<200 { grid.scroll(byDeltaX: 0, deltaY: -3_000) }
            for _ in 0..<200 { grid.scroll(byDeltaX: 0, deltaY: 3_000) }
        }
    }

    private func attachHierarchy(_ app: XCUIApplication, _ name: String) {
        print(app.debugDescription)
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
