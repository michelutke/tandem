import XCTest

/// E22-01 tdd: ui: menuBarExtra_pairedConnectedScenario_showsPeerNameAndBatteryPlaceholder
@MainActor
final class ScenarioPairedConnectedUITests: XCTestCase {
    func test_menuBarExtra_pairedConnectedScenario_showsPeerNameAndBatteryPlaceholder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "pairedConnected"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let label = window.staticTexts["menuBarStateLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "seeded pairedConnected label never appeared")
        // macOS exposes SwiftUI Text content as AXValue; label can be empty on headless runners.
        let value = label.value as? String ?? ""
        XCTAssertEqual(value.isEmpty ? label.label : value, "Connected to Pixel 8")

        let battery = window.staticTexts["batteryLabel"]
        XCTAssertTrue(battery.waitForExistence(timeout: 10), "battery placeholder never appeared")
        let batteryValue = battery.value as? String ?? ""
        XCTAssertEqual(batteryValue.isEmpty ? battery.label : batteryValue, "Battery: —")
    }

    // MARK: - menuBarExtra_pairedConnectedScenario_showsFourEnabledQuickActions

    func test_menuBarExtra_pairedConnectedScenario_showsFourEnabledQuickActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "pairedConnected"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let actions: [(identifier: String, label: String)] = [
            ("sendFileMenuItem", "Send File…"),
            ("pushClipboardMenuItem", "Push Clipboard"),
            ("findPhoneMenuItem", "Find Phone"),
            ("mirrorPhoneMenuItem", "Mirror Phone")
        ]

        for action in actions {
            let button = window.buttons[action.identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(action.identifier) never appeared")
            // As above: which AX attribute actually carries the text is unreliable on headless
            // runners, so accept either the button's title or its accessibility label.
            let gotTitle = button.title
            let gotLabel = button.label
            XCTAssertTrue(
                gotTitle == action.label || gotLabel == action.label,
                "expected title or label \"\(action.label)\", got title=\"\(gotTitle)\" label=\"\(gotLabel)\""
            )
            XCTAssertTrue(button.isEnabled, "\(action.identifier) should be enabled when connected")
        }
    }
}
