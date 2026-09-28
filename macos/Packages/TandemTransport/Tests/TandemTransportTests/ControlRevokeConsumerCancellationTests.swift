import Foundation
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
@testable import TandemProtocol
@testable import TandemTransport

/// E14-27 HIGH regression: proves ``startControlRevokeReader`` still dispatches a `Revoke` frame
/// to ``RevokeHandler/handle`` even when its returned `Task` is cancelled in the same race window
/// a real `awaitClose()` caller (``ListenerFactory``'s own `wireSession`) used to cancel it in --
/// a phone that sends `Revoke` then immediately closes the connection (Kotlin `UnpairAction`'s
/// delete-then-send-then-close ordering) used to be able to race `ChannelMultiplexer.finish(_:)`
/// against that cancellation such that `AsyncStream.next()` returned `nil` for an
/// already-buffered `Revoke` frame, silently skipping `trustStore.unpair` (AC-09/AC-12). The fix
/// (``ControlRevokeConsumer.swift``) makes the returned `Task` an inert proxy over a `worker` task
/// that is never itself cancelled, so cancelling the caller's handle can never interrupt a
/// `Revoke` that already arrived on the wire -- this test cancels the handle *before* the frame
/// even arrives, the strictest version of that race, and still expects full delivery.
@Suite("ControlRevokeConsumer cancellation resilience (E14-27)")
struct ControlRevokeConsumerCancellationTests {

    @Test(.timeLimit(.minutes(1)))
    func revokeReaderTaskCancelledBeforeFrameArrives_revokeStillHandled() async throws {
        let fixture = try await Self.makeReadySessionPair()
        let sessionRegistry = ControlSessionRegistry()
        await sessionRegistry.register(fixture.fingerprint, session: fixture.mac)

        let revokeReaderTask = startControlRevokeReader(
            fingerprint: fixture.fingerprint,
            session: fixture.mac,
            sessionRegistry: sessionRegistry,
            trustStore: fixture.trustStore
        )

        // The exact hazard this fix removes: cancel the caller's only handle on the reader before
        // the Revoke frame has even been sent, let alone dequeued -- the strictest possible version
        // of `wireSession`'s former `awaitClose()`-then-`cancel()` race. A pre-fix implementation
        // (a bare `Task { for await frame in frames { ... } }` returned directly) would have this
        // task's `Task.isCancelled` already `true` by the time the frame arrives, at risk of losing
        // it; the fix's inert proxy makes this a no-op against the real worker.
        revokeReaderTask?.cancel()

        try await fixture.peer.send(.control, payload: .revoke(Tandem_V1_Revoke()))

        let revoked = await waitUntilTrue(timeout: .seconds(2)) {
            let stillTrusted = (try? fixture.trustStore.get(fixture.fingerprint)) ?? nil
            let stillRegistered = await sessionRegistry.session(for: fixture.fingerprint) != nil
            return stillTrusted == nil && !stillRegistered
        }

        #expect(revoked)
        #expect(try fixture.trustStore.get(fixture.fingerprint) == nil)
        let stillRegistered = await sessionRegistry.session(for: fixture.fingerprint) != nil
        #expect(!stillRegistered)
    }

    private struct Fixture {
        let mac: ByteStreamSession
        let peer: ByteStreamSession
        let fingerprint: SpkiFingerprint
        let trustStore: TrustStore
    }

    /// Wires a `mac`/`peer` pair of `ByteStreamSession`s over one `InMemoryConnectionPair`, both
    /// driven straight to Ready (no real TLS/`VersionHandshake`, out of scope here) -- the same
    /// idiom `HeartbeatControllerTestSupport.Harness.make(clock:)` uses -- with a trust record for
    /// `mac`'s peer already seeded, so this test's body is just the race itself.
    private static func makeReadySessionPair() async throws -> Fixture {
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

        let fingerprint = try SpkiFingerprint(bytes: Data(repeating: 0x07, count: SpkiFingerprint.byteCount))
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        try trustStore.put(
            PeerRecord(
                fingerprint: fingerprint,
                displayName: "Test Phone",
                pairedAt: Date(timeIntervalSince1970: 0),
                lastSeen: Date(timeIntervalSince1970: 0),
                capabilities: []
            )
        )

        return Fixture(
            mac: ByteStreamSession(multiplexer: macMultiplexer, stateMachine: macStateMachine),
            peer: ByteStreamSession(multiplexer: peerMultiplexer, stateMachine: peerStateMachine),
            fingerprint: fingerprint,
            trustStore: trustStore
        )
    }
}
