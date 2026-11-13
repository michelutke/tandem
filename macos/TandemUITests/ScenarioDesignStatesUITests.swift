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
}
