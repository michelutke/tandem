import Foundation
import Testing
import TandemProtocol
@testable import TandemTestSupport
@testable import TandemTransport

/// E20-05: Mac half of the E01-07 liveness contract (`docs/protocol/SPEC.md` #heartbeat) --
/// ``HeartbeatController``'s idle-send `Heartbeat`, its dead-peer detection, and
/// `docs/planning/decisions.md` D-61's `CONTROL` receive cap. Every scenario wires two
/// `ByteStreamSession`s over one ``InMemoryConnectionPair`` (mirroring ``ByteStreamSession``'s own
/// doc comment): `mac` is the side under test, wired to a ``HeartbeatController``; `peer` stands
/// in for the phone.
///
/// Two ordering hazards are specific to driving `HeartbeatController` against a
/// `ManualTestClock` rather than wall-clock time:
///  - `start()`/a reset only *launches* a timer's `Task`, without waiting for it to actually reach
///    its `clock.sleep(for:)` call and register as a parked sleeper. A real `Clock` has no
///    observable "instant jump", so a scheduling delay before that call is immaterial there;
///    `ManualTestClock.advance(by:)` *does* have one, so calling it before a timer has parked
///    makes that timer's deadline compute against the *already advanced* `now`, silently pushing
///    it into the future. `waitForParkedSleepers(_:count:)` polls
///    `ManualTestClock.pendingSleeperCountForTesting` (internal, reached via `@testable import`)
///    before any test advances the clock.
///  - Every other "eventually true" assertion depends on further, separate, unstructured `Task`s
///    (the multiplexer's reader/writer loops, `HeartbeatController`'s observer loops, this file's
///    collectors) getting scheduled -- `waitUntilTrue(timeout:_:)` polls for these instead of
///    sleeping a fixed budget.
@Suite("HeartbeatController", .serialized)
struct HeartbeatControllerTests {

    @Test
    func macHeartbeat_idle15sWithoutSend_sendsHeartbeat() async throws {
        let harness = await Harness.make()
        defer { withExtendedLifetime(harness) {} }

        harness.clock.advance(by: HeartbeatController.sendIdleInterval)
        let arrived = await waitUntilTrue { await harness.peerControlFrames.frames.count >= 1 }
        #expect(arrived, "expected a Heartbeat within the timeout")

        let frames = await harness.peerControlFrames.frames
        #expect(frames.count == 1)
        guard case .heartbeat? = frames.first?.payload else {
            Issue.record("expected exactly one Heartbeat, got \(frames)")
            return
        }
    }

    @Test
    func macHeartbeat_frameSentAt10s_noHeartbeatBefore25s() async throws {
        let harness = await Harness.make()
        defer { withExtendedLifetime(harness) {} }

        harness.clock.advance(by: .seconds(10))
        try await harness.mac.send(.control, payload: .creditGrant(Self.noopControlFrame()))
        // The frame sent at t=10s must reset the idle-send timer -- and that reset's *own*
        // replacement timer must have actually parked -- before the clock moves again;
        // otherwise the original t=15s deadline (if still parked) fires regardless of this
        // reset, or the replacement (if it parks only after the next advance) computes its
        // deadline against the wrong `now`.
        let reset = await waitUntilTrue { await harness.controller.sendIdleResetCountForTesting >= 2 }
        #expect(reset, "the frame sent at t=10s must reset the idle-send timer")
        let reparked = await waitForParkedSleepers(harness.clock, count: 2)
        #expect(reparked)

        harness.clock.advance(by: .seconds(14)) // now t=24s
        await harness.settle()
        let framesAt24s = await harness.peerControlFrames.frames
        #expect(!Self.containsHeartbeat(framesAt24s), "no Heartbeat must be sent before t=25s")

        harness.clock.advance(by: .seconds(1)) // now t=25s
        let arrived = await waitUntilTrue { Self.containsHeartbeat(await harness.peerControlFrames.frames) }
        #expect(arrived, "exactly one Heartbeat must be sent by t=25s")
        let framesAt25s = await harness.peerControlFrames.frames
        #expect(framesAt25s.filter(Self.isHeartbeat).count == 1)
    }

    @Test
    func macHeartbeat_heartbeatReceived_noReplySent() async throws {
        let harness = await Harness.make()
        defer { withExtendedLifetime(harness) {} }

        try await harness.peer.send(.control, payload: .heartbeat(Tandem_V1_Heartbeat()))
        await harness.settle()

        // Well under the Mac's own independent 15s idle-send timer, so any frame observed here
        // would have to be a reply to the received Heartbeat, not the Mac's unrelated own timer.
        harness.clock.advance(by: .seconds(5))
        await harness.settle()

        let frames = await harness.peerControlFrames.frames
        #expect(frames.isEmpty, "a received Heartbeat must never cause a reply")
    }

    @Test
    func macDeadPeer_silent45sWithoutReceive_stateDead() async throws {
        let harness = await Harness.make()
        defer { withExtendedLifetime(harness) {} }

        harness.clock.advance(by: HeartbeatController.deadPeerThreshold)
        let becameDead = await waitUntilTrue { await harness.macState == .dead }
        #expect(becameDead)
        #expect(await harness.cancelled)
    }

    @Test
    func macDeadPeer_nonHeartbeatFrameAt44s_staysConnected() async throws {
        let harness = await Harness.make()
        defer { withExtendedLifetime(harness) {} }

        harness.clock.advance(by: .seconds(44))
        await harness.settle()
        try await harness.peer.send(.control, payload: .creditGrant(Self.noopControlFrame()))
        // Same ordering hazard as the send-side test above: confirm the reset actually happened,
        // and its replacement timer actually parked, before advancing past the original t=45s.
        let reset = await waitUntilTrue { await harness.controller.deadPeerResetCountForTesting >= 2 }
        #expect(reset, "the frame received at t=44s must reset the dead-peer timer")
        let reparked = await waitForParkedSleepers(harness.clock, count: 2)
        #expect(reparked)

        harness.clock.advance(by: .seconds(2)) // now t=46s
        await harness.settle()

        let state = await harness.macState
        #expect(state == .ready, "a non-Heartbeat frame received at t=44s must keep the connection up past t=45s")
    }

    @Test
    func macDeadPeer_oneConnectionDead_otherConnectionUnaffected() async throws {
        let clock = ManualTestClock()
        let harnessA = await Harness.make(clock: clock)
        let harnessB = await Harness.make(clock: clock)
        defer {
            withExtendedLifetime(harnessA) {}
            withExtendedLifetime(harnessB) {}
        }

        clock.advance(by: .seconds(1))
        try await harnessB.peer.send(.control, payload: .creditGrant(Self.noopControlFrame()))
        let resetB = await waitUntilTrue { await harnessB.controller.deadPeerResetCountForTesting >= 2 }
        #expect(resetB)
        let reparkedB = await waitForParkedSleepers(clock, count: 4) // A's 2 + B's 2
        #expect(reparkedB)

        clock.advance(by: .seconds(44)) // A: t=45s silent, B: t=44s since its own last receive
        let deadA = await waitUntilTrue { await harnessA.macState == .dead }
        #expect(deadA, "connection A must go dead on its own silent 45s")

        let stateB = await harnessB.macState
        #expect(stateB == .ready, "connection B must be unaffected by connection A going dead")
    }

    @Test
    func macControlChannel_peerControlFloodOver60FramesPerSecond_closesLimitExceeded() async throws {
        let harness = await Harness.make()
        defer { withExtendedLifetime(harness) {} }

        for _ in 0..<61 {
            try await harness.peer.send(.control, payload: .creditGrant(Self.noopControlFrame()))
        }
        let closed = await waitUntilTrue(timeout: .seconds(5)) {
            await harness.macState == .failed(.limitExceeded)
        }
        #expect(closed)
        #expect(await harness.cancelled)
    }

    /// D-66: unsolicited `Heartbeat`s the Mac receives count toward the same D-61 cap as
    /// non-`Heartbeat` `CONTROL` frames -- D-61's own wording alone excludes `Heartbeat`, which
    /// would let a compromised-but-authenticated phone flood unsolicited `Heartbeat`s past the cap.
    @Test
    func macControlChannel_peerHeartbeatFloodOver60FramesPerSecond_closesLimitExceeded() async throws {
        let harness = await Harness.make()
        defer { withExtendedLifetime(harness) {} }

        for _ in 0..<61 {
            try await harness.peer.send(.control, payload: .heartbeat(Tandem_V1_Heartbeat()))
        }
        let closed = await waitUntilTrue(timeout: .seconds(5)) {
            await harness.macState == .failed(.limitExceeded)
        }
        #expect(closed)
        #expect(await harness.cancelled)
    }

    // MARK: - Helpers

    /// A well-formed, harmless non-`Heartbeat` `CONTROL` frame stand-in: a bare
    /// `Tandem_V1_CreditGrant()` defaults `channel` to `.unspecified`, which is correctly rejected
    /// as malformed (naming a real feature channel with `amount = 0` is a legitimate no-op
    /// instead), silently closing that side's multiplexer if left unset.
    private static func noopControlFrame() -> Tandem_V1_CreditGrant {
        var grant = Tandem_V1_CreditGrant()
        grant.channel = .files
        grant.amount = 0
        return grant
    }

    private static func isHeartbeat(_ frame: InboundFrame) -> Bool {
        if case .heartbeat = frame.payload { return true }
        return false
    }

    private static func containsHeartbeat(_ frames: [InboundFrame]) -> Bool {
        frames.contains(where: isHeartbeat)
    }
}
