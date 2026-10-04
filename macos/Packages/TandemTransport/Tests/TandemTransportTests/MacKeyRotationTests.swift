import CryptoKit
import Foundation
import Synchronization
import Testing
import TandemCrypto
@testable import TandemProtocol
import TandemStore
import TandemTestSupport
@testable import TandemTransport

@Suite("MacKeyRotation")
struct MacKeyRotationTests {
    static let now = Date(timeIntervalSince1970: 3_000_000)
    static let challenge = Data(repeating: 0x7C, count: RotationVerifier.challengeByteCount)

    final class StubWindow: PairingWindowState {
        var isOpen: Bool { false }
        func admitCandidate() -> PairingCandidateToken? { nil }
        func releaseCandidate(_ token: PairingCandidateToken) {}
    }

    final class MemoryStore: NextRotationDueStore {
        private let value: Mutex<Date?>
        init(_ due: Date?) { value = Mutex(due) }
        func get() -> Date? { value.withLock { $0 } }
        func set(_ due: Date) { value.withLock { $0 = due } }
    }

    final class Counter: Sendable {
        private let value = Mutex(0)
        var count: Int { value.withLock { $0 } }
        func increment() { value.withLock { $0 += 1 } }
    }

    static func keyRotationCount(_ session: FakeTandemSession) async -> Int {
        await session.sent.filter { frame in
            if case .keyRotation = frame.payload { return true }
            return false
        }.count
    }

    static func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<20_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    @Test
    func macRotationComposition_keyTabAndScheduler_shareOneInitiator() async throws {
        let keychain = InMemoryKeychainStore()
        let trustStore = TrustStore(keychainStore: keychain)
        _ = try IdentityKeyProvider(keychainStore: keychain).getOrCreateIdentityKey()
        let phoneFingerprint = try SpkiFingerprint.of(spkiDer: P256.Signing.PrivateKey().publicKey.derRepresentation)
        try trustStore.put(PeerRecord(
            fingerprint: phoneFingerprint, displayName: "Phone", pairedAt: Self.now, lastSeen: Self.now,
            capabilities: []
        ))
        let switches = Counter()
        let rotation = MacKeyRotation(
            keychainStore: keychain,
            trustStore: trustStore,
            window: StubWindow(),
            dateProvider: { Self.now },
            clock: ManualTestClock(),
            interval: .seconds(365 * 86_400),
            dueStore: MemoryStore(Self.now.addingTimeInterval(-1)),
            onSwitched: { switches.increment() }
        )
        let session = FakeTandemSession()
        rotation.startScheduler()
        await rotation.attach(peer: phoneFingerprint, session: session)
        var challenge = Tandem_V1_RotationChallenge()
        challenge.challenge = Self.challenge
        await session.inject(InboundFrame(channel: .control, seq: 0, ack: 0, payload: .rotationChallenge(challenge)))

        #expect(await Self.eventually { await Self.keyRotationCount(session) == 1 })
        let keyTab = Task { await rotation.rotate() }
        for _ in 0..<200 { await Task.yield() }
        #expect(await Self.keyRotationCount(session) == 1)

        await session.inject(InboundFrame(
            channel: .control, seq: 1, ack: 0, payload: .rotationAck(Tandem_V1_RotationAck())))

        #expect(await keyTab.value == .switched)
        #expect(await Self.keyRotationCount(session) == 1)
        #expect(switches.count == 1)
    }

    @Test
    func macRotation_challengeInjectedAfterAnotherControlSubscriber_isStillDelivered() async throws {
        let keychain = InMemoryKeychainStore()
        let trustStore = TrustStore(keychainStore: keychain)
        _ = try IdentityKeyProvider(keychainStore: keychain).getOrCreateIdentityKey()
        let phoneFingerprint = try SpkiFingerprint.of(spkiDer: P256.Signing.PrivateKey().publicKey.derRepresentation)
        try trustStore.put(PeerRecord(
            fingerprint: phoneFingerprint, displayName: "Phone", pairedAt: Self.now, lastSeen: Self.now,
            capabilities: []
        ))
        let rotation = MacKeyRotation(
            keychainStore: keychain,
            trustStore: trustStore,
            window: StubWindow(),
            dateProvider: { Self.now },
            clock: ManualTestClock(),
            interval: .seconds(365 * 86_400),
            dueStore: MemoryStore(nil),
            onSwitched: {}
        )
        let session = FakeTandemSession()
        _ = await session.receive(.control)
        var challenge = Tandem_V1_RotationChallenge()
        challenge.challenge = Self.challenge
        await session.inject(InboundFrame(channel: .control, seq: 0, ack: 0, payload: .rotationChallenge(challenge)))
        await rotation.attach(peer: phoneFingerprint, session: session)

        let outcome = Task { await rotation.rotate() }

        #expect(await Self.eventually { await Self.keyRotationCount(session) == 1 })
        outcome.cancel()
    }
}
