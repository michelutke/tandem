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
    func pairingFailure_badProof_closesAndDecrementsByOne() async {
        let window = Self.makeWindow(verifierResult: false)
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        #expect(window.candidateHellosCompleted() != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink)

        await flow.pairRequestReceived(proof: Data([9]))

        #expect(window.attemptsRemaining == 2)
        #expect(!window.candidateInFlight)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    @Test
    func pairingFailure_malformedPairRequest_closesAndDecrementsByOne() async {
        let window = Self.makeWindow()
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        #expect(window.candidateHellosCompleted() != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink)

        await flow.wrongPayloadReceived()

        #expect(window.attemptsRemaining == 2)
        #expect(!window.candidateInFlight)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    @Test
    func pairingFailure_windowExpiresBeforeAccept_closesAndNoTrustCommitted() async {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock, verifierResult: true)
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        #expect(window.candidateHellosCompleted() != nil)
        #expect(window.submitPairRequest(proof: Data([9])) == .pendingConfirmation)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink)

        clock.advance(by: .seconds(120))
        await flow.heartbeatReceived()

        #expect(window.closedReason == .expired)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    @Test
    func pairingFailure_badProofThenDrop_decrementsExactlyOnce() async {
        let window = Self.makeWindow(verifierResult: false)
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        #expect(window.candidateHellosCompleted() != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink)

        await flow.pairRequestReceived(proof: Data([9]))
        flow.connectionClosed()

        #expect(window.attemptsRemaining == 2)
        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
    }

    @Test
    func pairingFailure_badProof_wireReasonPairingUnavailableOnly() async {
        let window = Self.makeWindow(verifierResult: false)
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        #expect(window.candidateHellosCompleted() != nil)
        let sink = FakePairingCandidateSink()
        let flow = PairingCandidateFlow(window: window, sink: sink)

        await flow.pairRequestReceived(proof: Data([9]))

        let reasons = sink.calls.compactMap { call -> PairRejectedWireReason? in
            guard case .pairRejected(let reason) = call else { return nil }
            return reason
        }
        #expect(reasons == [.pairingUnavailable])
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
