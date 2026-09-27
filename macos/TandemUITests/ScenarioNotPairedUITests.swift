import XCTest

/// E22-01 tdd: ui: menuBarExtra_notPairedScenario_showsNotPairedAndPairPhoneItem
@MainActor
final class ScenarioNotPairedUITests: XCTestCase {
    func test_menuBarExtra_notPairedScenario_showsNotPairedAndPairPhoneItem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "notPaired"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let label = window.staticTexts["menuBarStateLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "seeded notPaired label never appeared")
        // macOS exposes SwiftUI Text content as AXValue; label can be empty on headless runners.
        let value = label.value as? String ?? ""
        XCTAssertEqual(value.isEmpty ? label.label : value, "Not paired")

        let pairPhoneItem = window.buttons["pairPhoneMenuItem"]
        XCTAssertTrue(pairPhoneItem.waitForExistence(timeout: 10), "Pair phone… item never appeared")
        XCTAssertEqual(pairPhoneItem.title, "Pair phone…")
    }
}
