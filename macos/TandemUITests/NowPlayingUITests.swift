import XCTest

/// E72-08 tdd: nowPlayingView_seededNowPlaying_rendersTitleAndControls.
@MainActor
final class NowPlayingUITests: XCTestCase {
    func test_nowPlayingView_seededNowPlaying_rendersTitleAndControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "nowPlayingSeeded"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        XCTAssertTrue(window.staticTexts["nowPlayingTitle"].waitForExistence(timeout: 10), "title never appeared")
        XCTAssertTrue(window.staticTexts["nowPlayingArtist"].exists)
        XCTAssertTrue(window.buttons["nowPlayingPlayPause"].exists)
        XCTAssertTrue(window.buttons["nowPlayingNext"].exists)
        XCTAssertTrue(window.buttons["nowPlayingPrevious"].exists)
    }
}
