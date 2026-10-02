import FeatureNotifications
import Foundation
import Testing
import TandemCrypto
@testable import TandemProtocol
@preconcurrency import UserNotifications

@Suite struct NotificationDismissSyncTests {
    private static func dismiss(
        key: String,
        origin: Tandem_V1_NotificationDismiss.Origin
    ) -> Tandem_V1_NotificationDismiss {
        var dismiss = Tandem_V1_NotificationDismiss()
        dismiss.key = key
        dismiss.origin = origin
        return dismiss
    }

    @Test func macDismissSync_androidOriginDismiss_removesDeliveredWithKeyIdentifier() async throws {
        let presenter = RecordingNotificationPresenter()
        let session = FakeTandemSession()
        let sync = NotificationDismissSync(presenter: presenter, session: session)

        await sync.handle(Self.dismiss(key: "k-1", origin: .android))

        let removed = await presenter.removedIdentifierBatches
        #expect(removed == [["k-1"]])
    }

    @Test func macDismissSync_androidOriginDismiss_sendsNoDismissBack() async throws {
        let presenter = RecordingNotificationPresenter()
        let session = FakeTandemSession()
        let sync = NotificationDismissSync(presenter: presenter, session: session)

        await sync.handle(Self.dismiss(key: "k-2", origin: .android))

        let sent = await session.sent
        #expect(sent.isEmpty)
    }

    @Test func macDismissSync_userDismissAction_sendsDismissOriginMacos() async throws {
        let presenter = RecordingNotificationPresenter()
        let session = FakeTandemSession()
        let sync = NotificationDismissSync(presenter: presenter, session: session)

        await sync.handle(
            NotificationResponseEvent(
                requestIdentifier: "k-3",
                actionIdentifier: UNNotificationDismissActionIdentifier,
                userText: nil
            )
        )

        let sent = await session.sent
        #expect(sent == [
            FakeTandemSession.SentFrame(
                channel: .notify,
                payload: .notificationDismiss(Self.dismiss(key: "k-3", origin: .macos))
            )
        ])
        let removed = await presenter.removedIdentifierBatches
        #expect(removed.isEmpty)
    }

    @Test func macDismissSync_nonDismissAction_sendsNothing() async throws {
        let presenter = RecordingNotificationPresenter()
        let session = FakeTandemSession()
        let sync = NotificationDismissSync(presenter: presenter, session: session)

        await sync.handle(
            NotificationResponseEvent(
                requestIdentifier: "k-4",
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userText: nil
            )
        )

        let sent = await session.sent
        #expect(sent.isEmpty)
    }

    @Test func macDismissSync_readerRoutesAndroidDismissFrame() async throws {
        let presenter = RecordingNotificationPresenter()
        let coordinator = NotificationPresentationCoordinator(presenter: presenter)
        let session = FakeTandemSession()
        let sync = NotificationDismissSync(presenter: presenter, session: session)
        let peer = try SpkiFingerprint(bytes: Data(repeating: 0x06, count: 32))

        let readerTask = startNotificationPresentationReader(
            peer: peer, session: session, coordinator: coordinator, dismissSync: sync
        )
        await session.inject(
            InboundFrame(
                channel: .notify, seq: 1, ack: 0,
                payload: .notificationDismiss(Self.dismiss(key: "k-5", origin: .android))
            )
        )
        await session.close()
        await readerTask.value

        let removed = await presenter.removedIdentifierBatches
        #expect(removed == [["k-5"]])
    }
}
