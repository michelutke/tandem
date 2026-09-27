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
}
