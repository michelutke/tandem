import Foundation
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
@testable import TandemTransport

@Suite("RotationRollback")
struct RotationRollbackTests {
    static func advancePastAckDeadline(_ harness: RotationInitiatorTests.Harness) async {
        for _ in 0..<200 { await Task.yield() }
        harness.ackClock.advance(by: RotationInitiator.ackDeadline)
        for _ in 0..<200 { await Task.yield() }
    }

    @Test
    func macRotationRollback_noAckWithin30s_oldKeyRemainsActiveIdentity() async throws {
        let harness = try RotationInitiatorTests.Harness()
        let phone = try RotationInitiatorTests.Phone()
        try harness.pair(phone)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()
        let initiator = await RotationInitiatorTests.rotate(harness, phone)

        await Self.advancePastAckDeadline(harness)
        await initiator.receivedAck()

        #expect(try harness.activeSpki == oldSpki)
        #expect(harness.hasPendingKey)
        #expect(harness.switchCount.count == 0)
        #expect(try #require(try harness.coordinator.attempt()).pendingRecordIds.count == 1)
    }

    @Test
    func macRotationRollback_nextSessionAfterTimeout_resendsSamePendingNewSpki() async throws {
        let harness = try RotationInitiatorTests.Harness()
        let phone = try RotationInitiatorTests.Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        _ = await RotationInitiatorTests.rotate(harness, phone)
        let first = try #require(await RotationInitiatorTests.keyRotation(phone))
        await Self.advancePastAckDeadline(harness)

        let next = RotationInitiatorTests.Phone(reconnecting: phone)
        _ = await RotationInitiatorTests.rotate(harness, next)

        #expect(try #require(await RotationInitiatorTests.keyRotation(next)).newSpkiDer == first.newSpkiDer)
    }

    @Test
    func macRotationRollback_rotationRejectReceived_pendingKeyDeletedOldKeySole() async throws {
        let harness = try RotationInitiatorTests.Harness()
        let phone = try RotationInitiatorTests.Phone()
        try harness.pair(phone)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()
        let initiator = await RotationInitiatorTests.rotate(harness, phone)

        await initiator.receivedReject(.invalidSignature)

        #expect(try harness.activeSpki == oldSpki)
        #expect(!harness.hasPendingKey)
        #expect(try harness.coordinator.attempt() == nil)
        #expect(harness.switchCount.count == 0)
    }

    @Test
    func macRotationRollback_sessionDropBeforeAck_rotationStaysPending() async throws {
        let harness = try RotationInitiatorTests.Harness()
        let phone = try RotationInitiatorTests.Phone()
        try harness.pair(phone)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()
        _ = await RotationInitiatorTests.rotate(harness, phone)
        await phone.session.close()

        #expect(try harness.activeSpki == oldSpki)
        #expect(harness.hasPendingKey)
        #expect(try #require(try harness.coordinator.attempt()).pendingRecordIds.count == 1)
    }

    @Test
    func macRotationRollback_appRelaunch_pendingRotationResent() async throws {
        let harness = try RotationInitiatorTests.Harness()
        let phone = try RotationInitiatorTests.Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        _ = await RotationInitiatorTests.rotate(harness, phone)
        let first = try #require(await RotationInitiatorTests.keyRotation(phone))

        let clock = harness.clock
        let relaunched = RotationCoordinator(
            keychainStore: harness.keychain,
            trustStore: TrustStore(keychainStore: harness.keychain),
            window: harness.window,
            dateProvider: { clock.now }
        )
        try relaunched.resume()
        let challenge = RotationInitiatorTests.challenge
        let rotation = try relaunched.keyRotation(forRecordId: phone.fingerprint, challenge: challenge)

        #expect(try #require(rotation).newSpkiDer == first.newSpkiDer)
    }

    @Test
    func macRotationRollback_rejectAfterCommit_newKeyStaysActive() async throws {
        let harness = try RotationInitiatorTests.Harness()
        let phone = try RotationInitiatorTests.Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        let initiator = await RotationInitiatorTests.rotate(harness, phone)
        let sent = try #require(await RotationInitiatorTests.keyRotation(phone))
        await initiator.receivedAck()

        await initiator.receivedReject(.invalidSignature)

        #expect(try harness.activeSpki == sent.newSpkiDer)
    }

    @Test
    func macRotationRollback_rejectConcurrentWithFinalAck_activeKeyNeverDeleted() async throws {
        for _ in 0..<20 {
            let harness = try RotationInitiatorTests.Harness()
            let phone = try RotationInitiatorTests.Phone()
            try harness.pair(phone)
            let oldSpki = try harness.activeSpki
            try harness.coordinator.begin()
            let initiator = await RotationInitiatorTests.rotate(harness, phone)
            let sent = try #require(await RotationInitiatorTests.keyRotation(phone))

            async let ack: Void = initiator.receivedAck()
            async let reject: Void = initiator.receivedReject(.invalidSignature)
            _ = await (ack, reject)

            let active = try harness.activeSpki
            #expect(active == oldSpki || active == sent.newSpkiDer)
            #expect(try harness.coordinator.attempt() == nil)
        }
    }

    @Test
    func macRotationRollback_rejectWithoutSentFrame_ignored() async throws {
        let harness = try RotationInitiatorTests.Harness()
        let phone = try RotationInitiatorTests.Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()

        await harness.initiator(for: phone).receivedReject(.invalidSignature)

        #expect(harness.hasPendingKey)
        #expect(try #require(try harness.coordinator.attempt()).pendingRecordIds.count == 1)
    }

    @Test
    func macRotationRollback_rejectAfterPeerUnpaired_ignored() async throws {
        let harness = try RotationInitiatorTests.Harness()
        let phone = try RotationInitiatorTests.Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        let initiator = await RotationInitiatorTests.rotate(harness, phone)
        try harness.trustStore.unpair(phone.fingerprint)

        await initiator.receivedReject(.invalidSignature)

        #expect(harness.hasPendingKey)
        #expect(try harness.coordinator.attempt() != nil)
    }

    @Test
    func macRotationRollback_rejectAfterAckExpired_ignored() async throws {
        let harness = try RotationInitiatorTests.Harness()
        let phone = try RotationInitiatorTests.Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        let initiator = await RotationInitiatorTests.rotate(harness, phone)
        await Self.advancePastAckDeadline(harness)

        await initiator.receivedReject(.invalidSignature)

        #expect(harness.hasPendingKey)
        #expect(try #require(try harness.coordinator.attempt()).pendingRecordIds.count == 1)
    }
}
