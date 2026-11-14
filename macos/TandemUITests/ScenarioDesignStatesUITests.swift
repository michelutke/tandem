import XCTest

/// Design-conformance states (ui-spec §7.1, §8): each scenario seeds one state and the test checks
/// its exact copy or next-step control.
@MainActor
final class ScenarioDesignStatesUITests: XCTestCase {
    private func launch(_ scenario: String) -> XCUIElement {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", scenario]
        app.launch()
        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")
        return window
    }

    private func text(of element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return value.isEmpty ? element.label : value
    }

    func test_popoverRinging_showsStopRingingOnly() throws {
        let window = launch("popoverRinging")

        XCTAssertTrue(window.buttons["stopRingingMenuItem"].waitForExistence(timeout: 10))
        XCTAssertFalse(window.buttons["sendFileMenuItem"].exists)
    }

    func test_popoverUpdateNeeded_showsCheckForUpdate() throws {
        let window = launch("popoverUpdateNeeded")

        XCTAssertTrue(window.buttons["checkForUpdateMenuItem"].waitForExistence(timeout: 10))
    }

    func test_popoverUnpairedNotice_showsPeerUnpairedLine() throws {
        let window = launch("popoverUnpairedNotice")

        let notice = window.staticTexts["peerUnpairedNoticeLabel"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertEqual(text(of: notice), "Pixel 8 unpaired this Mac.")
    }

    func test_pairingPaired_showsDone() throws {
        let window = launch("pairingPaired")

        XCTAssertTrue(window.buttons["Done"].waitForExistence(timeout: 10))
    }

    func test_trustErrorBanner_offersPairAgainAndUnpair() throws {
        let window = launch("trustErrorBanner")

        XCTAssertTrue(window.buttons["failClosedBannerPairAgainButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(window.buttons["failClosedBannerUnpairButton"].exists)
        XCTAssertEqual(text(of: window.staticTexts["failClosedBannerTitle"]), "Key changed.")
    }

    func test_photosNoAccess_showsNotSharedState() throws {
        let window = launch("photosNoAccess")

        let state = window.staticTexts["photoNoAccessEmptyState"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        XCTAssertTrue(text(of: state).contains("Pixel 8 hasn't shared photos. Allow access in Tandem on the phone."))
    }

    func test_mirrorWaitingScreen_showsWaitingCopyAndCancel() throws {
        let window = launch("mirrorWaitingScreen")

        XCTAssertEqual(text(of: window.staticTexts["mirrorStatusTitle"]), "Waiting.")
        XCTAssertEqual(text(of: window.staticTexts["mirrorStatusDetail"]), "Accept on Pixel 8 to start.")
        XCTAssertTrue(window.buttons["Cancel"].exists)
    }

    func test_mirrorDeclinedScreen_showsDeclinedCopyAndClose() throws {
        let window = launch("mirrorDeclinedScreen")

        XCTAssertEqual(text(of: window.staticTexts["mirrorStatusTitle"]), "Declined.")
        XCTAssertEqual(text(of: window.staticTexts["mirrorStatusDetail"]), "Nothing was shared.")
        XCTAssertTrue(window.buttons["Close"].exists)
    }

    func test_mirrorToolbar_showsNavigationControlOnAndStop() throws {
        let window = launch("mirrorToolbar")

        XCTAssertTrue(window.buttons["Back"].waitForExistence(timeout: 10))
        XCTAssertTrue(window.buttons["Home"].exists)
        XCTAssertTrue(window.buttons["Recents"].exists)
        XCTAssertTrue(window.staticTexts["Control on"].exists)
        XCTAssertTrue(window.buttons["Stop"].exists)
    }

    func test_photoGridSelection_showsDownloadCountAndFooter() throws {
        let window = launch("photoGridSelection")

        XCTAssertTrue(window.buttons["Download 2"].waitForExistence(timeout: 10))
        XCTAssertEqual(text(of: window.staticTexts["photoGridFooter"]), "Loaded 3 of 3 · thumbnails cached locally")
    }
}
