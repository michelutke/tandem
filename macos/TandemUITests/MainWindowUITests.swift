import XCTest

/// E22-09 tdd: mainWindow_phoneOffline_sidebarShowsLastSeen, mainWindow_featureDisabledOnPhone_showsTurnedOffState.
/// Uses the same `-UITestScenario` test window as the other `Scenario*UITests` (E00-26): the
/// scenario renders ``MainWindowView`` directly, the same way `pairedConnected` etc. render their
/// own end state, rather than exercising "Open Tandem" first.
@MainActor
final class MainWindowUITests: XCTestCase {
    // MARK: - mainWindow_phoneOffline_sidebarShowsLastSeen

    func test_mainWindow_phoneOffline_sidebarShowsLastSeen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "mainWindowOffline"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let stateLabel = window.staticTexts["sidebarStateLabel"]
        XCTAssertTrue(stateLabel.waitForExistence(timeout: 10), "sidebarStateLabel never appeared")
        let value = stateLabel.value as? String ?? ""
        XCTAssertEqual(value.isEmpty ? stateLabel.label : value, "Offline · seen 14:02")
    }

    // MARK: - mainWindow_featureDisabledOnPhone_showsTurnedOffState

    func test_mainWindow_featureDisabledOnPhone_showsTurnedOffState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "mainWindowFeatureDisabled"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let emptyState = window.staticTexts["turnedOffEmptyState"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10), "turnedOffEmptyState never appeared")
        let value = emptyState.value as? String ?? ""
        XCTAssertEqual(value.isEmpty ? emptyState.label : value, "Turned off on the phone.")
    }
}
