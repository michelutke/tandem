import XCTest

/// E50-08 manual-run UI check: conversation_seeded_showsBubblesAndComposer.
@MainActor
final class ConversationUITests: XCTestCase {
    func test_conversation_seeded_showsBubblesAndComposer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "conversationSeeded"]
        app.launch()

        let window = app.windows["Tandem UI Test Scenario"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ui test scenario window never appeared")

        let list = window.descendants(matching: .any)["messageList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "messageList never appeared")
        let inbound = window.staticTexts["See you at 6"]
        if !inbound.waitForExistence(timeout: 10) { attachHierarchy(app, "conversation-hierarchy") }
        XCTAssertTrue(inbound.exists, "inbound bubble missing")
        XCTAssertTrue(window.staticTexts["On my way"].waitForExistence(timeout: 10), "outbound bubble missing")
        let callButton = window.descendants(matching: .any)["callButton"]
        XCTAssertTrue(callButton.waitForExistence(timeout: 10), "header Call button missing")
    }

    private func attachHierarchy(_ app: XCUIApplication, _ name: String) {
        print(app.debugDescription)
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
