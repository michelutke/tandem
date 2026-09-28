import FeatureNotifications
import Testing
import TandemProtocol

@Suite struct NotificationRequestBuilderTests {
    @Test func notificationPresentation_plainPostedTitleSubtitleBodyMapped() {
        var posted = Tandem_V1_NotificationPosted()
        posted.key = "key-1"
        posted.packageName = "com.example.app"
        posted.title = "New message"
        posted.text = "Hello there"

        let request = NotificationRequestBuilder.build(posted)

        #expect(request.identifier == "key-1")
        #expect(request.content.title == "New message")
        #expect(request.content.subtitle == "com.example.app")
        #expect(request.content.body == "Hello there")
    }

    @Test func notificationPresentation_messagingStyleTwoSendersBodyHasSenderPrefixedLines() {
        var posted = Tandem_V1_NotificationPosted()
        posted.key = "key-2"
        posted.packageName = "com.example.chat"
        posted.title = "Group chat"
        posted.text = "Hi there\nHow are you?"
        posted.messagingStyleSenders = ["Alice", "Bob"]

        let request = NotificationRequestBuilder.build(posted)

        #expect(request.content.body == "Alice: Hi there\nBob: How are you?")
    }

    @Test func notificationPresentation_sameKeyPostedTwiceRequestIdentifierReused() {
        var first = Tandem_V1_NotificationPosted()
        first.key = "shared-key"
        first.title = "First"
        first.text = "First body"

        var second = Tandem_V1_NotificationPosted()
        second.key = "shared-key"
        second.title = "Updated"
        second.text = "Updated body"

        let firstRequest = NotificationRequestBuilder.build(first)
        let secondRequest = NotificationRequestBuilder.build(second)

        #expect(firstRequest.identifier == secondRequest.identifier)
    }

    @Test func notificationPresentation_titleWithBidiOverrideOverCapSanitizedAndTruncated() {
        var posted = Tandem_V1_NotificationPosted()
        posted.key = "key-3"
        posted.packageName = "com.example.app"
        // U+202E (RIGHT-TO-LEFT OVERRIDE) must be stripped, and the remaining "a" run must be
        // truncated to the title cap (256) plus a trailing ellipsis.
        posted.title = "\u{202E}" + String(repeating: "a", count: 300)
        posted.text = "body"

        let request = NotificationRequestBuilder.build(posted)

        #expect(!request.content.title.contains("\u{202E}"))
        #expect(request.content.title == String(repeating: "a", count: 256) + "\u{2026}")
    }

    @Test func notificationPresentation_oversizedSenderListTruncatedToCap() {
        var posted = Tandem_V1_NotificationPosted()
        posted.key = "key-4"
        posted.title = "Group chat"
        posted.messagingStyleSenders = (1...30).map { "Sender\($0)" }
        posted.text = (1...30).map { "line \($0)" }.joined(separator: "\n")

        let request = NotificationRequestBuilder.build(posted)

        let lines = request.content.body.components(separatedBy: "\n")
        #expect(lines.count == NotificationRequestBuilder.maxSenders)
        #expect(lines.first == "Sender1: line 1")
        #expect(lines.last == "Sender25: line 25")
    }
}
