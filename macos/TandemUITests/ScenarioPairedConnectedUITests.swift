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

    /// E23-04 tdd: ui: menuBarExtra_seededDeviceStatus_showsBatteryPercentAndNetworkLabel.
    /// `-UITestSeedDeviceStatus` (in addition to `-UITestScenario pairedConnected`) seeds a
    /// `DeviceStatus` on the same scenario session, so this asserts the real formatted
    /// battery/network text -- unlike the placeholder test above, which never seeds one.
    func test_menuBarExtra_seededDeviceStatus_showsBatteryPercentAndNetworkLabel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "pairedConnected", "-UITestSeedDeviceStatus"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let label = window.staticTexts["menuBarStateLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "seeded pairedConnected label never appeared")

        let battery = window.staticTexts["batteryLabel"]
        XCTAssertTrue(battery.waitForExistence(timeout: 10), "battery label never appeared")
        XCTAssertTrue(
            Self.waitForText(battery, toEqual: "Battery 82% · Charging"),
            "battery label never showed the seeded DeviceStatus's formatted text"
        )

        let network = window.staticTexts["networkLabel"]
        XCTAssertTrue(network.waitForExistence(timeout: 10), "network label never appeared")
        XCTAssertTrue(
            Self.waitForText(network, toEqual: "Wi-Fi"),
            "network label never showed the seeded DeviceStatus's network text"
        )
    }

    /// Polls `element`'s AXValue (falling back to its label -- both can be unreliable on headless
    /// runners, as elsewhere in this file) until it equals `expected`. The `DeviceStatus` seed is
    /// injected asynchronously (`TandemApp.swift`'s `ScenarioView`), so unlike this file's other
    /// assertions -- which read a value already stable by the time their element exists -- this
    /// one needs to keep polling after `waitForExistence` succeeds; `XCTNSPredicateExpectation`
    /// does that without a real-time sleep loop.
    private static func waitForText(
        _ element: XCUIElement,
        toEqual expected: String,
        timeout: TimeInterval = 10
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            let value = element.value as? String ?? ""
            return (value.isEmpty ? element.label : value) == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
