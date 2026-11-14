import Foundation
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
@testable import TandemProtocol
@testable import TandemTransport

@Suite("ControlRevokeConsumer registry adapter")
struct ControlRevokeRegistryTests {

    @Test(.timeLimit(.minutes(1)))
    func revoke_secondSessionUnderGracePin_closedThroughRealRegistry() async throws {
        let gracePin = try Self.fingerprint(0x01)
        let primaryPin = try Self.fingerprint(0x02)
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        try trustStore.put(
            PeerRecord(
                fingerprint: primaryPin,
                displayName: "Test Phone",
                pairedAt: Date(timeIntervalSince1970: 0),
                lastSeen: Date(timeIntervalSince1970: 0),
                capabilities: [],
                gracePin: GracePin(fingerprint: gracePin, expiresAt: Date(timeIntervalSince1970: 1_000))
            )
        )
        let oldSession = try await Self.makeReadySessionPair()
        let newSession = try await Self.makeReadySessionPair()
        let sessionRegistry = ControlSessionRegistry()
        await sessionRegistry.register(gracePin, session: oldSession.mac)
        await sessionRegistry.register(primaryPin, session: newSession.mac)

        _ = startControlRevokeReader(
            fingerprint: primaryPin,
            session: newSession.mac,
            sessionRegistry: sessionRegistry,
            trustStore: trustStore
        )
        try await newSession.peer.send(.control, payload: .revoke(Tandem_V1_Revoke()))

        let oldStream = await oldSession.mac.receive(.control)
        for await _ in oldStream {}
        let oldStillRegistered = await sessionRegistry.session(for: gracePin) != nil
        let newStillRegistered = await sessionRegistry.session(for: primaryPin) != nil
        #expect(!oldStillRegistered)
        #expect(!newStillRegistered)
        #expect(try trustStore.list().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func revoke_newerSessionUnderRevokingPin_closedThroughRealRegistry() async throws {
        let pin = try Self.fingerprint(0x03)
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        try trustStore.put(
            PeerRecord(
                fingerprint: pin,
                displayName: "Test Phone",
                pairedAt: Date(timeIntervalSince1970: 0),
                lastSeen: Date(timeIntervalSince1970: 0),
                capabilities: []
            )
        )
        let revokingSession = try await Self.makeReadySessionPair()
        let reconnected = try await Self.makeReadySessionPair()
        let sessionRegistry = ControlSessionRegistry()
        await sessionRegistry.register(pin, session: reconnected.mac)

        _ = startControlRevokeReader(
            fingerprint: pin,
            session: revokingSession.mac,
            sessionRegistry: sessionRegistry,
            trustStore: trustStore
        )
        try await revokingSession.peer.send(.control, payload: .revoke(Tandem_V1_Revoke()))

        let reconnectedStream = await reconnected.mac.receive(.control)
        for await _ in reconnectedStream {}
        #expect(await sessionRegistry.session(for: pin) == nil)
        #expect(try trustStore.list().isEmpty)
    }

    private struct SessionPair {
        let mac: ByteStreamSession
        let peer: ByteStreamSession
    }

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private static func makeReadySessionPair() async throws -> SessionPair {
        let pair = InMemoryConnectionPair()
        let macMultiplexer = ChannelMultiplexer(
            source: ByteStreamConnectionFrameSource(pair.endA),
            sink: pair.endA.send
        )
        let peerMultiplexer = ChannelMultiplexer(
            source: ByteStreamConnectionFrameSource(pair.endB),
            sink: pair.endB.send
        )
        await macMultiplexer.start()
        await peerMultiplexer.start()

        let clock = ManualTestClock()
        let macStateMachine = ConnectionStateMachine(clock: clock)
        let peerStateMachine = ConnectionStateMachine(clock: clock)
        for stateMachine in [macStateMachine, peerStateMachine] {
            await stateMachine.handle(.incomingConnection)
            await stateMachine.handle(.handshakeStarted)
            await stateMachine.handle(.handshakeCompleted)
            await stateMachine.handle(.compatibleHelloReceived)
        }
        return SessionPair(
            mac: ByteStreamSession(multiplexer: macMultiplexer, stateMachine: macStateMachine),
            peer: ByteStreamSession(multiplexer: peerMultiplexer, stateMachine: peerStateMachine)
        )
    }
}
