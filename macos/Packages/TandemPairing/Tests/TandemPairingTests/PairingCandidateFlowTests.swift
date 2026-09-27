import Foundation
import Testing
import TandemTestSupport
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
        let token = try #require(window.admitCandidateToken())
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
        let token = try #require(window.admitCandidateToken())
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
        let token = try #require(window.admitCandidateToken())
        #expect(window.candidateHellosCompleted(token) != nil)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        clock.advance(by: .seconds(120))
        await flow.heartbeatReceived()

        #expect(window.closedReason == .expired)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    @Test
    func pairingFailure_badProofThenDrop_decrementsExactlyOnce() async throws {
        let window = Self.makeWindow(verifierResult: false)
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidateToken())
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
        let token = try #require(window.admitCandidateToken())
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
        let token = try #require(window.admitCandidateToken())
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

    @Test
    func pairingCandidate_heartbeatAfterOwnerAccepted_neverFailsTheNewlyPairedSession() async throws {
        let window = Self.makeWindow()
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidateToken())
        #expect(window.candidateHellosCompleted(token) != nil)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        #expect(window.ownerAccepted())
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)

        await flow.heartbeatReceived()

        #expect(sink.calls.isEmpty)
    }

    @Test
    func pairingCandidate_connectionClosedWithStaleToken_doesNotBurnNewCandidatesAttempt() throws {
        let window = Self.makeWindow()
        window.open(secret: Data([1]))
        let staleToken = try #require(window.admitCandidateToken())
        #expect(window.candidateHellosCompleted(staleToken) != nil)
        let sink = FakePairingCandidateSink()
        let staleFlow = PairingCandidateFlow(window: window, sink: sink, token: staleToken)

        // This candidate's slot was freed by some other path (e.g. the window's own 10 s
        // deadline), and a brand new, unrelated candidate has since claimed it -- `staleFlow`
        // never itself failed (`hasFailed` is still false), so only the window's own token check
        // stands between a late `connectionClosed()` and burning the wrong candidate's attempt.
        window.releaseCandidate(staleToken)
        _ = try #require(window.admitCandidateToken())
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
