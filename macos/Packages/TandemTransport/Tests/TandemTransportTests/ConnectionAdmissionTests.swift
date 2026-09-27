import Foundation
import Testing
import TandemTestSupport
@testable import TandemTransport

/// SPEC.md §10 "Pre-authentication deadlines and connection caps" (E12-18): pre-auth connection
/// caps (8 total / 2 per source IP), the 10 s TLS handshake deadline, and the per-IP
/// failed-handshake throttle (>= 10 failures in 60 s -> refused for 60 s). Exercised as a pure
/// actor against ``ManualTestClock`` -- no real socket or TLS handshake anywhere in this file;
/// that's ``ListenerLoopbackTests``' job.
@Suite("ConnectionAdmission")
struct ConnectionAdmissionTests {

    @Test
    func connectionAdmission_ninthPreAuthConnection_refused() async {
        let admission = ConnectionAdmission(clock: ManualTestClock())

        for index in 0..<8 {
            let decision = await admission.accept(ipAddress: "10.0.0.\(index)", onHandshakeDeadline: {})
            #expect(decision.isAdmitted, "connection \(index) should be admitted")
        }

        let ninth = await admission.accept(ipAddress: "10.0.0.99", onHandshakeDeadline: {})

        #expect(ninth == .refused)
    }

    @Test
    func connectionAdmission_thirdPreAuthFromSameIp_refused() async {
        let admission = ConnectionAdmission(clock: ManualTestClock())

        let first = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})
        let second = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})
        let third = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})

        #expect(first.isAdmitted)
        #expect(second.isAdmitted)
        #expect(third == .refused)
    }

    @Test
    func connectionAdmission_handshakeNotDoneIn10s_closed() async {
        let clock = ManualTestClock()
        let admission = ConnectionAdmission(clock: clock)
        let closed = ClosedFlag()

        let decision = await admission.accept(ipAddress: "10.0.0.1") { closed.set() }
        #expect(decision.isAdmitted)
        for _ in 0..<10 { await Task.yield() }

        clock.advance(by: ConnectionAdmission.tlsHandshakeDeadline)
        for _ in 0..<10 { await Task.yield() }

        #expect(closed.value)

        // The slot must also be freed -- a fresh connection from the same IP is now admitted
        // again, exactly as if the timed-out connection had never been open.
        let again = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})
        #expect(again.isAdmitted)
    }

    @Test
    func connectionAdmission_handshakeCompletedBeforeDeadline_neverClosed() async {
        let clock = ManualTestClock()
        let admission = ConnectionAdmission(clock: clock)
        let closed = ClosedFlag()

        let decision = await admission.accept(ipAddress: "10.0.0.1") { closed.set() }
        guard case .admitted(let id) = decision else {
            Issue.record("expected an admitted decision")
            return
        }
        await admission.handshakeSucceeded(id)
        for _ in 0..<10 { await Task.yield() }

        clock.advance(by: ConnectionAdmission.tlsHandshakeDeadline)
        for _ in 0..<10 { await Task.yield() }

        #expect(!closed.value)
    }

    @Test
    func connectionAdmission_tenFailuresIn60sFromIp_ipRefusedFor60s() async {
        let clock = ManualTestClock()
        let admission = ConnectionAdmission(clock: clock)

        for _ in 0..<ConnectionAdmission.failureThreshold {
            let decision = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})
            guard case .admitted(let id) = decision else {
                Issue.record("expected an admitted decision while under both caps")
                return
            }
            await admission.handshakeFailed(id)
        }

        let refused = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})
        #expect(refused == .refused)

        for _ in 0..<20 { await Task.yield() } // let the throttle-clear task start racing its deadline
        clock.advance(by: ConnectionAdmission.ipRefusalDuration)
        for _ in 0..<20 { await Task.yield() } // let it resolve into the actor

        let admittedAgain = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})
        #expect(admittedAgain.isAdmitted)
    }

    @Test
    func connectionAdmission_throttledIp_otherIpStillAdmitted() async {
        let clock = ManualTestClock()
        let admission = ConnectionAdmission(clock: clock)

        for _ in 0..<ConnectionAdmission.failureThreshold {
            let decision = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})
            guard case .admitted(let id) = decision else {
                Issue.record("expected an admitted decision while under both caps")
                return
            }
            await admission.handshakeFailed(id)
        }

        let refusedA = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})
        let admittedB = await admission.accept(ipAddress: "10.0.0.2", onHandshakeDeadline: {})

        #expect(refusedA == .refused)
        #expect(admittedB.isAdmitted)
    }

    @Test
    func connectionAdmission_cancelAllReady_cancelsEachTrackedReadyConnectionOnce() async {
        let admission = ConnectionAdmission(clock: ManualTestClock())
        let decision = await admission.accept(ipAddress: "10.0.0.1", onHandshakeDeadline: {})
        guard case .admitted(let id) = decision else {
            Issue.record("expected an admitted decision")
            return
        }
        await admission.handshakeSucceeded(id)

        let cancelCount = CallCounter()
        await admission.trackReadyConnection(id) { cancelCount.increment() }

        await admission.cancelAllReady()
        await admission.cancelAllReady()

        #expect(cancelCount.value == 1, "a connection already cancelled must not be cancelled twice")
    }

    @Test
    func peerAuthorizer_signature_takesNoAddressOrAdmissionInput() {
        // Compile-time check (SPEC.md §10, invariant 3): `PeerAuthorizer.decide` has exactly this
        // shape -- a source address or admission decision anywhere in its parameter list would
        // fail this assignment to compile, since the throttle above must never be able to grant
        // trust.
        let decide: (Data, any TrustStoreReader, any PairingWindowState) -> PeerAuthorizationDecision
            = PeerAuthorizer.decide
        _ = decide
    }
}

private extension ConnectionAdmission.AdmissionDecision {
    var isAdmitted: Bool {
        if case .admitted = self { return true }
        return false
    }
}

/// Lock-free is fine here -- every call in this file happens from the single `MainActor`/test
/// task, `await`ed in order; this box just gives ``ConnectionAdmission``'s escaping
/// `onHandshakeDeadline` closure somewhere to record into.
private final class ClosedFlag: @unchecked Sendable {
    private(set) var value = false

    func set() {
        value = true
    }
}

/// Same shape as ``ClosedFlag``, counting instead of latching -- used to prove a cancel closure
/// runs exactly once even across repeated ``ConnectionAdmission/cancelAllReady()`` calls.
private final class CallCounter: @unchecked Sendable {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
