import XCTest

/// E22-05 tdd: the Settings window shell -- General, Notifications, Files and Privacy tabs. Paired
/// devices live in the main window's Devices section. Uses the same `-UITestScenario` test window
/// as the other `Scenario*UITests` (E00-26): the real status-bar item is unreliable to find/click
/// on headless CI runners, so `settingsMenuItem` in the always-present test window stands in for
/// it -- it calls the same `openSettings()` environment action a real menu bar click would.
@MainActor
final class SettingsWindowUITests: XCTestCase {
    private func launchToScenarioWindow(_ app: XCUIApplication) -> XCUIElement {
        app.launchArguments = ["-UITestScenario", "notPaired"]
        app.launch()
        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")
        return window
    }

    // MARK: - settingsWindow_openedFromMenuBarItem_generalTabSelected

    func test_settingsWindow_openedFromMenuBarItem_generalTabSelected() throws {
        let app = XCUIApplication()
        let window = launchToScenarioWindow(app)

        let settingsButton = window.buttons["settingsMenuItem"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "settingsMenuItem never appeared")
        settingsButton.click()

        let toggle = app.descendants(matching: .any)["launchAtLoginToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "General tab was not selected when Settings opened")
    }

    // MARK: - settingsWindow_cmdCommaWhileKey_opensSettings

    func test_settingsWindow_cmdCommaWhileKey_opensSettings() throws {
        let app = XCUIApplication()
        let window = launchToScenarioWindow(app)
        window.click()

        app.typeKey(",", modifierFlags: .command)

        let toggle = app.descendants(matching: .any)["launchAtLoginToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Cmd-, never opened the Settings window")
    }

    // MARK: - settingsWindow_toggleChangedThenTabSwitchedBack_valueRetained

    func test_settingsWindow_toggleChangedThenTabSwitchedBack_valueRetained() throws {
        let app = XCUIApplication()
        let window = launchToScenarioWindow(app)
        window.buttons["settingsMenuItem"].click()

        let toggle = app.descendants(matching: .any)["launchAtLoginToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "launchAtLoginToggle never appeared")
        // `.value`'s underlying dynamic type for a macOS checkbox isn't guaranteed to be `String`
        // (it can bridge as `NSNumber`/`Bool` depending on the AX runtime) -- `as? String` can
        // silently produce `nil` on both sides of a comparison even when the checkbox's real
        // state did change, making this assertion pass or fail for the wrong reason.
        // `String(describing:)` always captures the actual value's description instead.
        let initialValue = String(describing: toggle.value as Any)
        toggle.click()
        let toggledValue = String(describing: toggle.value as Any)
        XCTAssertNotEqual(initialValue, toggledValue, "toggle never changed on click")

        let notificationsTab = app.buttons["notificationsTab"]
        XCTAssertTrue(notificationsTab.waitForExistence(timeout: 10), "notificationsTab never appeared")
        notificationsTab.click()

        let generalTab = app.buttons["generalTab"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 10), "generalTab never appeared")
        generalTab.click()

        let toggleAfterSwitch = app.descendants(matching: .any)["launchAtLoginToggle"]
        XCTAssertTrue(toggleAfterSwitch.waitForExistence(timeout: 10), "launchAtLoginToggle never reappeared")
        XCTAssertEqual(
            String(describing: toggleAfterSwitch.value as Any),
            toggledValue,
            "toggle value was not retained across a tab switch"
        )
    }

    // MARK: - macRotationSettings_seededSuccessScenario_rendersNewFingerprint

    func test_macRotationSettings_seededSuccessScenario_rendersNewFingerprint() throws {
        let app = XCUIApplication()
        let window = launchToScenarioWindow(app)
        window.buttons["settingsMenuItem"].click()

        let toggle = app.descendants(matching: .any)["launchAtLoginToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Settings window never opened")
        app.buttons["privacyTab"].click()

        let rotateButton = app.buttons["Rotate key"]
        XCTAssertTrue(rotateButton.waitForExistence(timeout: 10), "Rotate key button never appeared")
        rotateButton.click()
        let confirmButton = app.buttons["Rotate"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 10), "confirmation never appeared")
        confirmButton.click()

        let newFingerprint = app.staticTexts["rotationNewFingerprint"]
        XCTAssertTrue(newFingerprint.waitForExistence(timeout: 10), "new fingerprint never rendered")
        let text = newFingerprint.value as? String ?? ""
        let rendered = text.isEmpty ? newFingerprint.label : text
        XCTAssertTrue(rendered.contains("DD:EE:FF:02"), "new fingerprint text was \(rendered)")
    }
}
