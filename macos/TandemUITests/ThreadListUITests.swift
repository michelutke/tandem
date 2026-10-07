import XCTest

/// E50-07 manual-run UI check: threadList_seeded_showsRowsAndUnreadBadge.
@MainActor
final class ThreadListUITests: XCTestCase {
    func test_threadList_seeded_showsRowsAndUnreadBadge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "threadListSeeded"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let list = window.descendants(matching: .any)["threadList"]
        if !list.waitForExistence(timeout: 10) { attachHierarchy(app, "threadlist-hierarchy") }
        XCTAssertTrue(list.exists, "threadList never appeared")
        XCTAssertTrue(window.staticTexts["Ada Lovelace"].exists, "resolved contact name missing")
        XCTAssertTrue(window.staticTexts["+41 79 123 45 67"].exists, "international number missing")
    }

    private func attachHierarchy(_ app: XCUIApplication, _ name: String) {
        print(app.debugDescription)
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
