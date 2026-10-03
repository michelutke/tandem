import CryptoKit
import Foundation
import Synchronization
import Testing
import TandemCrypto
import TandemProtocol
import TandemStore
import TandemTestSupport
@testable import TandemTransport

@Suite("RotationInitiator")
struct RotationInitiatorTests {
    static let start = Date(timeIntervalSince1970: 3_000_000)
    static let challenge = Data(repeating: 0x7C, count: RotationVerifier.challengeByteCount)

    final class Clock: Sendable {
        private let current = Mutex(RotationInitiatorTests.start)
        var now: Date { current.withLock { $0 } }
        func advance(by interval: TimeInterval) { current.withLock { $0.addTimeInterval(interval) } }
    }

    final class StubWindow: PairingWindowState {
        let open = Mutex(false)
        var isOpen: Bool { open.withLock { $0 } }
        func admitCandidate() -> PairingCandidateToken? { nil }
        func releaseCandidate(_ token: PairingCandidateToken) {}
    }

    struct Phone {
        let fingerprint: SpkiFingerprint
        let session = FakeTandemSession()

        init() throws {
            fingerprint = try SpkiFingerprint.of(spkiDer: P256.Signing.PrivateKey().publicKey.derRepresentation)
        }
    }

    final class Counter: Sendable {
        private let value = Mutex(0)
        var count: Int { value.withLock { $0 } }
        func increment() { value.withLock { $0 += 1 } }
    }

    final class Harness: Sendable {
        let keychain = InMemoryKeychainStore()
        let trustStore: TrustStore
        let clock = Clock()
        let window = StubWindow()
        let coordinator: RotationCoordinator
        let switchCount = Counter()
        let ackClock = ManualTestClock()

        init() throws {
            trustStore = TrustStore(keychainStore: keychain)
            let clock = clock
            let switchCount = switchCount
            coordinator = RotationCoordinator(
                keychainStore: keychain,
                trustStore: trustStore,
                window: window,
                dateProvider: { clock.now },
                onSwitched: { switchCount.increment() }
            )
            _ = try IdentityKeyProvider(keychainStore: keychain).getOrCreateIdentityKey()
        }

        var activeSpki: Data { get throws { try RotationKeyProvider(keychainStore: keychain).activeSpkiDer() } }

        func pair(_ phone: Phone) throws {
            try trustStore.put(PeerRecord(
                fingerprint: phone.fingerprint, displayName: "Phone",
                pairedAt: clock.now, lastSeen: clock.now, capabilities: []
            ))
        }

        func initiator(for phone: Phone) -> RotationInitiator {
            let clock = clock
            return RotationInitiator(
                session: phone.session,
                handshakeFingerprint: phone.fingerprint,
                coordinator: coordinator,
                trustStore: trustStore,
                window: window,
                dateProvider: { clock.now },
                clock: ackClock
            )
        }

        var hasPendingKey: Bool {
            guard let tag = try? IdentityKeySlots(keychainStore: keychain).inactiveTag() else { return false }
            return (try? keychain.copyKey(tag: tag)) != nil
        }
    }

    static func keyRotation(_ phone: Phone) async -> Tandem_V1_KeyRotation? {
        for frame in await phone.session.sent.reversed() {
            if case .keyRotation(let message) = frame.payload { return message }
        }
        return nil
    }

    static func rotate(_ harness: Harness, _ phone: Phone) async -> RotationInitiator {
        let initiator = harness.initiator(for: phone)
        await initiator.receivedChallenge(challenge)
        return initiator
    }

    @Test
    func macRotationInitiator_unauthenticatedSession_noKeyRotationFrameSent() async throws {
        let harness = try Harness()
        try harness.pair(try Phone())
        try harness.coordinator.begin()
        let stranger = try Phone()

        _ = await Self.rotate(harness, stranger)

        #expect(await Self.keyRotation(stranger) == nil)
        #expect(await stranger.session.sent.isEmpty)
    }

    @Test
    func macRotationInitiator_pairingWindowSession_noKeyRotationFrameSent() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        harness.window.open.withLock { $0 = true }

        _ = await Self.rotate(harness, phone)

        #expect(await Self.keyRotation(phone) == nil)
    }

    @Test
    func macRotationInitiator_pairingWindowOpen_noRotationStarted() throws {
        let harness = try Harness()
        try harness.pair(try Phone())
        harness.window.open.withLock { $0 = true }

        #expect(throws: RotationCoordinatorError.pairingWindowOpen) { try harness.coordinator.begin() }
        #expect(try harness.coordinator.attempt() == nil)
        #expect(!harness.hasPendingKey)
    }

    @Test
    func macRotationInitiator_authenticatedSession_signatureVerifiesWithOldPublicKey() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()

        _ = await Self.rotate(harness, phone)

        let message = try #require(await Self.keyRotation(phone))
        #expect(RotationVerifier.verify(
            oldSpkiDer: try harness.activeSpki,
            newSpkiDer: message.newSpkiDer,
            challenge: Self.challenge,
            sigOldKey: message.sigOldKey,
            sigNewKey: message.sigNewKey
        ))
    }

    @Test
    func macRotationInitiator_sentFrame_bothSignaturesCoverReceivedRotationChallenge() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()

        _ = await Self.rotate(harness, phone)

        let message = try #require(await Self.keyRotation(phone))
        let otherChallenge = Data(repeating: 0x01, count: RotationVerifier.challengeByteCount)
        #expect(!RotationVerifier.verify(
            oldSpkiDer: try harness.activeSpki,
            newSpkiDer: message.newSpkiDer,
            challenge: otherChallenge,
            sigOldKey: message.sigOldKey,
            sigNewKey: message.sigNewKey
        ))
    }

    @Test
    func macRotationInitiator_beforeAck_oldKeyRemainsActiveIdentity() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()

        _ = await Self.rotate(harness, phone)

        #expect(try harness.activeSpki == oldSpki)
        #expect(harness.hasPendingKey)
        #expect(harness.switchCount.count == 0)
    }

    @Test
    func macRotationInitiator_ackReceived_newKeyActiveAndOldItemDeleted() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()
        let initiator = await Self.rotate(harness, phone)
        let sent = try #require(await Self.keyRotation(phone))

        await initiator.receivedAck()

        #expect(try harness.activeSpki == sent.newSpkiDer)
        #expect(try harness.activeSpki != oldSpki)
        #expect(!harness.hasPendingKey)
        #expect(try harness.coordinator.attempt() == nil)
        #expect(harness.switchCount.count == 1)
    }

    @Test
    func macRotationInitiator_oneOfTwoPhonesAcked_listenerKeepsOldIdentity() async throws {
        let harness = try Harness()
        let first = try Phone(), second = try Phone()
        try harness.pair(first)
        try harness.pair(second)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()

        let initiator = await Self.rotate(harness, first)
        await initiator.receivedAck()

        #expect(try harness.activeSpki == oldSpki)
        #expect(harness.hasPendingKey)
        #expect(try #require(try harness.coordinator.attempt()).pendingRecordIds.count == 1)
    }

    @Test
    func macRotationInitiator_allPhonesAcked_listenerSwitchesAndOldItemDeleted() async throws {
        let harness = try Harness()
        let first = try Phone(), second = try Phone()
        try harness.pair(first)
        try harness.pair(second)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()

        await Self.rotate(harness, first).receivedAck()
        let secondInitiator = await Self.rotate(harness, second)
        let sent = try #require(await Self.keyRotation(second))
        await secondInitiator.receivedAck()

        #expect(try harness.activeSpki == sent.newSpkiDer)
        #expect(try harness.activeSpki != oldSpki)
        #expect(!harness.hasPendingKey)
    }

    @Test
    func macRotationInitiator_ackWithoutSentFrame_ignored() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()

        await harness.initiator(for: phone).receivedAck()

        #expect(harness.hasPendingKey)
        #expect(try #require(try harness.coordinator.attempt()).pendingRecordIds.count == 1)
    }

    @Test
    func macRotationInitiator_finishWithPendingPhone_unpairsPendingThenSwitches() async throws {
        let harness = try Harness()
        let acked = try Phone(), pending = try Phone()
        try harness.pair(acked)
        try harness.pair(pending)
        try harness.coordinator.begin()
        await Self.rotate(harness, acked).receivedAck()

        #expect(throws: RotationCoordinatorError.finishNotYetAvailable) { try harness.coordinator.finish() }
        harness.clock.advance(by: TrustStore.gracePinLifetime)
        try harness.coordinator.finish()

        #expect(try harness.trustStore.get(pending.fingerprint) == nil)
        #expect(try harness.trustStore.get(acked.fingerprint) != nil)
        #expect(!harness.hasPendingKey)
        #expect(try harness.coordinator.attempt() == nil)
    }
}
