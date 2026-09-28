import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
import TandemTransport
@testable import TandemPairing

/// The pairing-candidate flow handler (E14-09, `docs/protocol/SPEC.md` §2 "Frame order on a
/// pairing-candidate connection"): every failure path this issue covers -- bad proof, a wrong
/// (malformed) payload, and the window closing mid-flight -- closes the connection and burns at
/// most one attempt per connection. Mid-flight expiry is driven with `ManualTestClock`, exactly
/// like `PairingWindowTests`.
@Suite("PairingCandidateFlow")
struct PairingCandidateFlowTests {

    @Test
    func pairingFailure_badProof_closesAndDecrementsByOne() async throws {
        let window = Self.makeWindow(verifierResult: false)
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        await flow.pairRequestReceived(proof: Data([9]))

        #expect(window.attemptsRemaining == 2)
        #expect(!window.candidateInFlight)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    @Test
    func pairingFailure_malformedPairRequest_closesAndDecrementsByOne() async throws {
        let window = Self.makeWindow()
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        await flow.wrongPayloadReceived()

        #expect(window.attemptsRemaining == 2)
        #expect(!window.candidateInFlight)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    @Test
    func pairingFailure_windowExpiresBeforeAccept_closesAndNoTrustCommitted() async throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock, verifierResult: true)
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        clock.advance(by: .seconds(120))
        await flow.heartbeatReceived()

        #expect(window.closedReason == .expired)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    // MARK: - E14-24: whole-window-expiry race (deadlineBurnedToken never set)

    /// Regression for the second, narrower race the E14-16 fix's `deadlineBurnedToken` doesn't
    /// cover: here it's the window's own 120 s *whole-window* expiry -- not the candidate's 10 s
    /// sub-deadline -- that `settleLocked()` processes first (stood in for by
    /// `PairingViewModel.tick()`'s 1 Hz poll reading `closedReason`, exactly like production). That
    /// branch returns before ever reaching the per-candidate deadline check, so
    /// `deadlineBurnedToken` is never set; `tick()` then regenerates, which nils it outright. The
    /// active 10 s watcher's `requestDeadlineElapsed()` call must still close this stale connection
    /// rather than conclude (wrongly) that some other path already handled it.
    @Test
    func pairingCandidateFlow_windowExpiresBeforeCandidateDeadlineCheck_connectionClosed() async throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock)
        let viewModel = PairingViewModel(
            window: window,
            fingerprint: try SpkiFingerprint(bytes: Data(repeating: 0xAB, count: SpkiFingerprint.byteCount)),
            secretSource: SystemSecretSource(),
            addressSource: FakeLocalAddressSource(addresses: ["192.168.1.10"]),
            port: 54321,
            name: "Mac",
            dateProvider: FixedDateProvider(clock: clock).provider
        )
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        // The window's own 120 s expiry, not the candidate's 10 s sub-deadline.
        clock.advance(by: .seconds(120))
        // Stands in for `PairingViewModel.tick()`'s 1 Hz UI poll racing the watcher below: this
        // settles the whole-window expiry first, then regenerates -- both before the watcher fires.
        viewModel.tick()

        // The active 10 s watcher, firing after the race above already ran.
        await flow.requestDeadlineElapsed()

        #expect(sink.calls == [.closePairingFailed])
    }

    /// Pins why ``PairingCandidateFlow/requestDeadlineElapsed()``'s fix must rely on
    /// ``PairingWindow/requestDeadlineElapsed(_:)``'s own tri-state scoped to its own stale `token`
    /// (E14-25), not a window-wide in-flight check -- a window-wide check would see a fresh
    /// candidate already admitted (true) and wrongly no-op, leaving the stale connection open
    /// (reintroducing the exact bug this file's other E14-24 test guards against). The stale
    /// watcher must close only its own connection and never touch the fresh candidate's slot.
    @Test
    func pairingCandidateFlow_staleWatcherAfterFreshCandidateAdmitted_closesStaleOnlyNotFresh() async throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock)
        let viewModel = PairingViewModel(
            window: window,
            fingerprint: try SpkiFingerprint(bytes: Data(repeating: 0xAB, count: SpkiFingerprint.byteCount)),
            secretSource: SystemSecretSource(),
            addressSource: FakeLocalAddressSource(addresses: ["192.168.1.10"]),
            port: 54321,
            name: "Mac",
            dateProvider: FixedDateProvider(clock: clock).provider
        )
        let staleToken = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(staleToken) != nil)
        let staleSink = FakePairingCandidateSink()
        let staleFlow = PairingCandidateFlow(window: window, sink: staleSink, token: staleToken)

        clock.advance(by: .seconds(120))
        viewModel.tick()

        let freshToken = try #require(window.admitCandidate())
        #expect(freshToken != staleToken)
        #expect(window.candidateInFlight)

        await staleFlow.requestDeadlineElapsed()

        #expect(staleSink.calls == [.closePairingFailed])
        #expect(window.candidateInFlight, "the fresh candidate's slot must be untouched by the stale watcher")
    }

    @Test
    func pairingFailure_badProofThenDrop_decrementsExactlyOnce() async throws {
        let window = Self.makeWindow(verifierResult: false)
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        await flow.pairRequestReceived(proof: Data([9]))
        flow.connectionClosed()

        #expect(window.attemptsRemaining == 2)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    @Test
    func pairingFailure_wrongPayloadThenConnectionClosed_decrementsExactlyOnce() async throws {
        let window = Self.makeWindow()
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        await flow.wrongPayloadReceived()
        flow.connectionClosed()

        // Once this candidate has already failed via `wrongPayloadReceived()`, `connectionClosed()`
        // no-ops entirely (finding, cycle 8 adversarial review) rather than touching `window` again.
        #expect(window.attemptsRemaining == 2)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    @Test
    func pairingFailure_badProof_wireReasonPairingUnavailableOnly() async throws {
        let window = Self.makeWindow(verifierResult: false)
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        await flow.pairRequestReceived(proof: Data([9]))

        let reasons = sink.calls.compactMap { call -> PairRejectedWireReason? in
            guard case .pairRejected(let reason) = call else { return nil }
            return reason
        }
        #expect(reasons == [.pairingUnavailable])
    }

    // MARK: - E14-16 finding #4: heartbeat race during `pair()`'s `PairAccepted` send

    @Test
    func heartbeatReceived_windowAlreadyPaired_noPairRejectedSent() async throws {
        let window = Self.makeWindow(verifierResult: true)
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        // Simulates `PairConfirmationViewModel.pair()` having already committed the window's
        // `.paired` transition (its very first side effect) while it is still suspended sending
        // `PairAccepted` -- a `Heartbeat` landing on this connection's own frame loop in exactly
        // that window must never be treated as this candidate failing.
        #expect(window.ownerAccepted(token))

        await flow.heartbeatReceived()

        #expect(window.closedReason == .paired)
        #expect(sink.calls.isEmpty)
    }

    // MARK: - E14-16 finding #5: active `PairRequest` deadline

    @Test
    func requestDeadlineElapsed_beforeAnyRequest_closesWithNoPairRejectedAndBurnsOneAttempt() async throws {
        let window = Self.makeWindow()
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        await flow.requestDeadlineElapsed()

        #expect(window.attemptsRemaining == 2)
        #expect(!window.candidateInFlight)
        #expect(sink.calls == [.closePairingFailed])
    }

    @Test
    func requestDeadlineElapsed_afterValidRequestAlreadyPending_noOp() async throws {
        let window = Self.makeWindow(verifierResult: true)
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        // A delayed deadline timer firing after a valid `PairRequest` already arrived must never
        // burn the attempt or close the connection a second time.
        await flow.requestDeadlineElapsed()

        #expect(window.isConfirmationPending)
        #expect(window.attemptsRemaining == 3)
        #expect(sink.calls.isEmpty)
    }

    @Test
    func pairingCandidate_connectionClosedWithStaleToken_doesNotBurnNewCandidatesAttempt() throws {
        let window = Self.makeWindow()
        window.open(secret: Data([1]))
        let staleToken = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(staleToken) != nil)
        let sink = FakePairingCandidateSink()
        let staleFlow = PairingCandidateFlow(window: window, sink: sink, token: staleToken)

        // This candidate's slot was freed by some other path (e.g. the window's own 10 s
        // deadline), and a brand new, unrelated candidate has since claimed it -- `staleFlow`
        // never itself failed (`hasFailed` is still false), so only the window's own token check
        // stands between a late `connectionClosed()` and burning the wrong candidate's attempt.
        window.releaseCandidate(staleToken)
        _ = try #require(window.admitCandidate())
        let attemptsBeforeStaleClose = window.attemptsRemaining

        staleFlow.connectionClosed()

        #expect(window.attemptsRemaining == attemptsBeforeStaleClose)
        #expect(window.candidateInFlight)
    }

    private static func makeWindow(
        clock: ManualTestClock = ManualTestClock(),
        verifierResult: Bool = true
    ) -> PairingWindow {
        PairingWindow(
            dateProvider: FixedDateProvider(clock: clock).provider,
            proofVerifier: SpyPairRequestVerifier(result: verifierResult)
        )
    }
}
