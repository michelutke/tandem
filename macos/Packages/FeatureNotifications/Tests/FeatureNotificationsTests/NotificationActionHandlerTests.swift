import FeatureNotifications
import Foundation
import Testing
@testable import TandemProtocol

@Suite struct NotificationActionHandlerTests {
    private static func sentActions(_ session: FakeTandemSession) async -> [Tandem_V1_NotificationAction] {
        await session.sent.compactMap { frame in
            guard frame.channel == .notify, case .notificationAction(let action) = frame.payload else { return nil }
            return action
        }
    }

    @Test func actionResponseHandler_actionTapIndexOne_sendsActionIndexOneWithoutReplyText() async {
        let session = FakeTandemSession()
        let handler = NotificationActionHandler(presenter: RecordingNotificationPresenter(), session: session)

        await handler.handle(
            NotificationResponseEvent(
                requestIdentifier: "key-1",
                actionIdentifier: "tandem.category.abc.action-1",
                userText: nil
            )
        )

        let actions = await Self.sentActions(session)
        #expect(actions.count == 1)
        #expect(actions.first?.key == "key-1")
        #expect(actions.first?.actionIndex == 1)
        #expect(actions.first?.replyText == "")
    }

    @Test func actionResponseHandler_textInputReply_sendsReplyTextVerbatim() async {
        let session = FakeTandemSession()
        let handler = NotificationActionHandler(presenter: RecordingNotificationPresenter(), session: session)
        let reply = "  hi\tthere \u{1F600}\n"

        await handler.handle(
            NotificationResponseEvent(
                requestIdentifier: "key-2",
                actionIdentifier: "tandem.category.abc.action-0",
                userText: reply
            )
        )

        let actions = await Self.sentActions(session)
        #expect(actions.count == 1)
        #expect(actions.first?.actionIndex == 0)
        #expect(actions.first?.replyText == reply)
    }

    @Test func actionResponseHandler_nonActionIdentifier_sendsNothing() async {
        let session = FakeTandemSession()
        let handler = NotificationActionHandler(presenter: RecordingNotificationPresenter(), session: session)

        await handler.handle(
            NotificationResponseEvent(
                requestIdentifier: "key-3",
                actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
                userText: nil
            )
        )

        #expect(await Self.sentActions(session).isEmpty)
    }

    @Test func actionResultHandler_statusGone_removesDeliveredAndShowsNoLongerAvailable() async {
        let presenter = RecordingNotificationPresenter()
        let handler = NotificationActionHandler(presenter: presenter, session: FakeTandemSession())
        var result = Tandem_V1_NotificationActionResult()
        result.key = "key-4"
        result.status = .gone

        await handler.handle(result)

        #expect(await presenter.removedIdentifierBatches == [["key-4"]])
        #expect(await presenter.addedBodies == ["Notification no longer available on phone"])
    }

    @Test func actionResultHandler_statusOk_doesNothing() async {
        let presenter = RecordingNotificationPresenter()
        let handler = NotificationActionHandler(presenter: presenter, session: FakeTandemSession())
        var result = Tandem_V1_NotificationActionResult()
        result.key = "key-5"
        result.status = .ok

        await handler.handle(result)

        #expect(await presenter.removedIdentifierBatches.isEmpty)
        #expect(await presenter.addedBodies.isEmpty)
    }
}
