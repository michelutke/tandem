import CryptoKit
import Foundation
import Synchronization
import Testing
import TandemCrypto
import TandemProtocol
import TandemStore
import TandemTestSupport
@testable import TandemTransport

@Suite("RotationReceiver")
struct RotationReceiverTests {
    private static let now = Date(timeIntervalSince1970: 2_000_000)
    private static let challenge = Data(repeating: 0x5A, count: RotationVerifier.challengeByteCount)

    private final class Rejections: Sendable {
        private let reasons = Mutex<[Tandem_V1_RotationRejectReason]>([])
        var all: [Tandem_V1_RotationRejectReason] { reasons.withLock { $0 } }
        func record(_ reason: Tandem_V1_RotationRejectReason) { reasons.withLock { $0.append(reason) } }
    }

    private struct Phone {
        let key = P256.Signing.PrivateKey()
        var spkiDer: Data { key.publicKey.derRepresentation }
        var fingerprint: SpkiFingerprint { get throws { try SpkiFingerprint.of(spkiDer: spkiDer) } }

        func record(name: String = "Phone") throws -> PeerRecord {
            PeerRecord(
                fingerprint: try fingerprint, displayName: name,
                pairedAt: RotationReceiverTests.now, lastSeen: RotationReceiverTests.now, capabilities: []
            )
        }
    }

    private struct Harness {
        let session = FakeTandemSession()
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let rejections = Rejections()
        let receiver: RotationReceiver

        init(
            handshake: Phone,
            windowOpen: Bool = false,
            challenge: Data = RotationReceiverTests.challenge,
            keychain: InMemoryKeychainStore = InMemoryKeychainStore()
        ) throws {
            let store = TrustStore(keychainStore: keychain)
            let rejections = self.rejections
            receiver = RotationReceiver(
                session: session,
                handshakeFingerprint: try handshake.fingerprint,
                handshakeSpkiDer: handshake.spkiDer,
                trustStore: store,
                configuration: RotationReceiverConfiguration(
                    window: StubWindow(isOpen: windowOpen),
                    dateProvider: { RotationReceiverTests.now },
                    challengeSource: { challenge },
                    onRejected: { rejections.record($0) }
                )
            )
            self.store = store
        }

        let store: TrustStore
    }

    private struct StubWindow: PairingWindowState {
        let isOpen: Bool
        func admitCandidate() -> PairingCandidateToken? { nil }
        func releaseCandidate(_ token: PairingCandidateToken) {}
    }

    private static func rotation(
        old: Phone, new: Phone, challenge: Data = challenge, sigNewBy: P256.Signing.PrivateKey? = nil
    ) throws -> Tandem_V1_KeyRotation {
        let transcript = Data("tandem-rotate-v1".utf8) + lp(old.spkiDer) + lp(new.spkiDer) + lp(challenge)
        var message = Tandem_V1_KeyRotation()
        message.newSpkiDer = new.spkiDer
        message.sigOldKey = try old.key.signature(for: transcript).derRepresentation
        message.sigNewKey = try (sigNewBy ?? new.key).signature(for: transcript).derRepresentation
        return message
    }

    private static func lp(_ value: Data) -> Data {
        Data([UInt8(value.count >> 8), UInt8(value.count & 0xFF)]) + value
    }

    private static func reply(_ harness: Harness) async -> [Tandem_V1_Envelope.OneOf_Payload] {
        await harness.session.sent.map(\.payload)
    }

    private static func rejectReason(_ harness: Harness) async -> Tandem_V1_RotationRejectReason? {
        for payload in await reply(harness) {
            if case .rotationReject(let reject) = payload { return reject.reason }
        }
        return nil
    }

    private static func acked(_ harness: Harness) async -> Bool {
        await reply(harness).contains { if case .rotationAck = $0 { true } else { false } }
    }

    @Test
    func sendChallenge_onReadySession_sends32ByteChallengeOnControl() async throws {
        let phone = Phone()
        let harness = try Harness(handshake: phone)

        await harness.receiver.sendChallenge()

        let sent = await harness.session.sent
        #expect(sent.count == 1)
        #expect(sent.first?.channel == .control)
        guard case .rotationChallenge(let message)? = sent.first?.payload else {
            Issue.record("expected RotationChallenge")
            return
        }
        #expect(message.challenge == Self.challenge)
    }

    @Test
    func handle_validRotation_pinsNewKeyKeepsOldAsGraceAndAcks() async throws {
        let old = Phone(), new = Phone()
        let harness = try Harness(handshake: old)
        try harness.store.put(try old.record())
        await harness.receiver.sendChallenge()

        await harness.receiver.handle(try Self.rotation(old: old, new: new))

        #expect(await Self.acked(harness))
        let record = try #require(try harness.store.get(try new.fingerprint))
        #expect(record.gracePin?.fingerprint == (try old.fingerprint))
        #expect(harness.rejections.all.isEmpty)
    }

    @Test
    func handle_invalidSignature_rejectsAndTrustStoreUnchanged() async throws {
        let old = Phone(), new = Phone(), stranger = Phone()
        let harness = try Harness(handshake: old)
        let before = try old.record()
        try harness.store.put(before)
        await harness.receiver.sendChallenge()

        await harness.receiver.handle(try Self.rotation(old: old, new: new, sigNewBy: stranger.key))

        #expect(await Self.rejectReason(harness) == .invalidSignature)
        #expect(try harness.store.list() == [before])
        #expect(harness.rejections.all == [.invalidSignature])
    }

    @Test
    func handle_unpinnedHandshake_rejectsUnauthenticatedSession() async throws {
        let old = Phone(), new = Phone()
        let harness = try Harness(handshake: old)
        await harness.receiver.sendChallenge()

        await harness.receiver.handle(try Self.rotation(old: old, new: new))

        #expect(await Self.rejectReason(harness) == .unauthenticatedSession)
        #expect(try harness.store.list().isEmpty)
    }

    @Test
    func handle_graceKeySessionForDifferentNewKey_rejectsNotPrimaryPin() async throws {
        let old = Phone(), rotated = Phone(), other = Phone()
        let harness = try Harness(handshake: old)
        let record = try old.record()
        try harness.store.put(record)
        try harness.store.rotatePrimary(of: record, to: try rotated.fingerprint, now: Self.now)
        await harness.receiver.sendChallenge()

        await harness.receiver.handle(try Self.rotation(old: old, new: other))

        #expect(await Self.rejectReason(harness) == .notPrimaryPin)
        #expect(try harness.store.get(try rotated.fingerprint)?.gracePin?.fingerprint == (try old.fingerprint))
    }

    @Test
    func handle_graceKeySessionResendOfPinnedNewKey_acksWithoutStateChange() async throws {
        let old = Phone(), new = Phone()
        let harness = try Harness(handshake: old)
        let record = try old.record()
        try harness.store.put(record)
        try harness.store.rotatePrimary(of: record, to: try new.fingerprint, now: Self.now)
        let before = try harness.store.list()

        await harness.receiver.handle(try Self.rotation(old: old, new: new, challenge: Data(count: 32)))

        #expect(await Self.acked(harness))
        #expect(try harness.store.list() == before)
    }

    @Test
    func handle_rotationFromPhoneA_otherPhoneRecordUnchanged() async throws {
        let phoneA = Phone(), phoneB = Phone(), newA = Phone()
        let harness = try Harness(handshake: phoneA)
        let recordB = try phoneB.record(name: "B")
        try harness.store.put(try phoneA.record(name: "A"))
        try harness.store.put(recordB)
        await harness.receiver.sendChallenge()

        await harness.receiver.handle(try Self.rotation(old: phoneA, new: newA))

        #expect(await Self.acked(harness))
        #expect(try harness.store.get(try phoneB.fingerprint) == recordB)
    }

    @Test
    func handle_rotationReplayedFromAnotherSession_rejectsInvalidSignature() async throws {
        let old = Phone(), new = Phone()
        let otherSession = try Harness(handshake: old, challenge: Data(repeating: 0x77, count: 32))
        try otherSession.store.put(try old.record())
        await otherSession.receiver.sendChallenge()

        await otherSession.receiver.handle(try Self.rotation(old: old, new: new, challenge: Self.challenge))

        #expect(await Self.rejectReason(otherSession) == .invalidSignature)
    }

    @Test
    func handle_newKeyEqualsOtherPhonesPin_rejectsDuplicateKey() async throws {
        let phoneA = Phone(), phoneB = Phone()
        let harness = try Harness(handshake: phoneA)
        try harness.store.put(try phoneA.record())
        try harness.store.put(try phoneB.record())
        await harness.receiver.sendChallenge()

        await harness.receiver.handle(try Self.rotation(old: phoneA, new: phoneB))

        #expect(await Self.rejectReason(harness) == .duplicateKey)
        #expect(try harness.store.get(try phoneA.fingerprint) != nil)
    }

    @Test
    func handle_pairingWindowOpen_rejectsRotationUnavailable() async throws {
        let old = Phone(), new = Phone()
        let harness = try Harness(handshake: old, windowOpen: true)
        try harness.store.put(try old.record())
        await harness.receiver.sendChallenge()

        await harness.receiver.handle(try Self.rotation(old: old, new: new))

        #expect(await Self.rejectReason(harness) == .rotationUnavailable)
        #expect(try harness.store.get(try old.fingerprint) != nil)
    }

    @Test
    func handle_secondRotationOnSameSession_rejectsInvalidSignatureChallengeConsumed() async throws {
        let old = Phone(), first = Phone(), second = Phone()
        let harness = try Harness(handshake: old)
        try harness.store.put(try old.record())
        await harness.receiver.sendChallenge()
        let bad = try Self.rotation(old: old, new: first, sigNewBy: Phone().key)
        await harness.receiver.handle(bad)

        await harness.receiver.handle(try Self.rotation(old: old, new: second))

        #expect(harness.rejections.all == [.invalidSignature, .invalidSignature])
        #expect(try harness.store.get(try second.fingerprint) == nil)
    }

    @Test
    func handle_nonP256NewKey_rejectsBeforeConsumingChallenge() async throws {
        let old = Phone(), new = Phone()
        let harness = try Harness(handshake: old)
        try harness.store.put(try old.record())
        await harness.receiver.sendChallenge()
        var p384 = Tandem_V1_KeyRotation()
        p384.newSpkiDer = P384.Signing.PrivateKey().publicKey.derRepresentation
        p384.sigOldKey = Data(count: 70)
        p384.sigNewKey = Data(count: 70)
        await harness.receiver.handle(p384)

        await harness.receiver.handle(try Self.rotation(old: old, new: new))

        #expect(harness.rejections.all == [.invalidSignature])
        #expect(await Self.acked(harness))
    }

    @Test
    func handle_everyReject_emitsExactlyOneEventPerReject() async throws {
        let old = Phone(), new = Phone()
        let harness = try Harness(handshake: old, windowOpen: true)
        try harness.store.put(try old.record())

        await harness.receiver.handle(try Self.rotation(old: old, new: new))
        await harness.receiver.handle(try Self.rotation(old: old, new: new))

        #expect(harness.rejections.all.count == 2)
        let rejectFrames = await Self.reply(harness).filter { if case .rotationReject = $0 { true } else { false } }
        #expect(rejectFrames.count == 2)
    }

    @Test
    func handle_keychainLockedDuringRead_rejectsAndStoreUntouched() async throws {
        let old = Phone(), new = Phone()
        let keychain = InMemoryKeychainStore()
        let harness = try Harness(handshake: old, keychain: keychain)
        let before = try old.record()
        try harness.store.put(before)
        await harness.receiver.sendChallenge()

        keychain.failNextOperation(with: .locked)
        await harness.receiver.handle(try Self.rotation(old: old, new: new))

        #expect(await Self.rejectReason(harness) == .rotationUnavailable)
        #expect(try harness.store.list() == [before])
    }
}
