import FeatureNotifications
import Foundation
import Testing
import TandemCrypto
@testable import TandemProtocol

@Suite struct NotificationPresentationCoordinatorTests {
    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: 32))
    }

    @Test func notificationPresentation_peerUnpairedDeliveredNotificationsRemoved() async throws {
        let presenter = RecordingNotificationPresenter()
        let coordinator = NotificationPresentationCoordinator(presenter: presenter)
        let peerA = try Self.fingerprint(0x01)
        let peerB = try Self.fingerprint(0x02)

        var fromA = Tandem_V1_NotificationPosted()
        fromA.key = "a-1"
        fromA.title = "From A"
        fromA.text = "body"

        var fromB = Tandem_V1_NotificationPosted()
        fromB.key = "b-1"
        fromB.title = "From B"
        fromB.text = "body"

        await coordinator.present(fromA, from: peerA)
        await coordinator.present(fromB, from: peerB)

        try await coordinator.purgeAll(peer: peerA)

        let removedBatches = await presenter.removedIdentifierBatches
        #expect(removedBatches == [["a-1"]])

        let addedIdentifiers = await presenter.addedIdentifiers
        #expect(addedIdentifiers.sorted() == ["a-1", "b-1"])
    }

    @Test func notificationPresentation_peerWithNoNotificationsPurgeIsNoOp() async throws {
        let presenter = RecordingNotificationPresenter()
        let coordinator = NotificationPresentationCoordinator(presenter: presenter)
        let peer = try Self.fingerprint(0x03)

        try await coordinator.purgeAll(peer: peer)

        let removedBatches = await presenter.removedIdentifierBatches
        #expect(removedBatches.isEmpty)
    }

    @Test func notificationPresentation_readerPresentsFramesFromFakeSession() async throws {
        let presenter = RecordingNotificationPresenter()
        let coordinator = NotificationPresentationCoordinator(presenter: presenter)
        let peer = try Self.fingerprint(0x04)
        let session = FakeTandemSession()

        var posted = Tandem_V1_NotificationPosted()
        posted.key = "reader-1"
        posted.title = "Reader test"
        posted.text = "body"

        let readerTask = startNotificationPresentationReader(peer: peer, session: session, coordinator: coordinator)

        await session.inject(
            InboundFrame(channel: .notify, seq: 1, ack: 0, payload: .notificationPosted(posted))
        )
        await session.close()
        await readerTask.value

        let addedIdentifiers = await presenter.addedIdentifiers
        #expect(addedIdentifiers == ["reader-1"])
    }
}
