import Foundation
import Testing
import TandemTestSupport
@testable import TandemPairing

/// ``PairingWindow``'s candidate-token safety net (cycle 8 adversarial review, D-73): a stale
/// caller from a since-released or since-replaced candidate can only ever no-op, never mutate or
/// burn an attempt for whichever candidate currently holds the single slot. Split out of
/// `PairingWindowTests` to keep both files under the project's type-body-length limit.
@Suite("PairingWindow candidate tokens")
struct PairingWindowCandidateTokenTests {

    @Test
    func pairingWindow_ownerAccepted_secretBytesActuallyZeroed() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([0xAA, 0xBB, 0xCC]))
        let token = try #require(window.admitCandidateToken())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        let box = try #require(window.secretBoxForTesting)

        #expect(window.ownerAccepted())

        // The literal same buffer `submitPairRequest` read from is scrubbed in place, not merely
        // dropped -- `secretBoxForTesting == nil` alone doesn't prove that.
        #expect(box.bytes.allSatisfy { $0 == 0 })
    }

    @Test
    func pairingWindow_ownerAccepted_windowExpiredWhileDialogPending_noOpReturnsFalse() throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidateToken())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)

        clock.advance(by: .seconds(120))

        #expect(!window.ownerAccepted())
        #expect(window.closedReason == .expired)
    }

    @Test
    func pairingWindow_admitCandidateTokenAfterRelease_staleTokenNoLongerReleasesNewCandidate() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let staleToken = try #require(window.admitCandidateToken())
        window.releaseCandidate(staleToken)
        #expect(window.attemptsRemaining == 2)

        _ = try #require(window.admitCandidateToken())

        // A late release from the connection that already burned its own attempt (e.g. its
        // transport close callback firing after the fact) MUST NOT touch the new candidate now
        // occupying the slot.
        window.releaseCandidate(staleToken)

        #expect(window.candidateInFlight)
        #expect(window.attemptsRemaining == 2)
    }

    @Test
    func pairingWindow_submitPairRequestWithStaleToken_rejectedWithoutAffectingNewCandidate() throws {
        let verifier = SpyPairRequestVerifier(result: true)
        let window = Self.makeWindow(clock: ManualTestClock(), verifier: verifier).window
        window.open(secret: Data([1]))
        let staleToken = try #require(window.admitCandidateToken())
        window.releaseCandidate(staleToken)
        let currentToken = try #require(window.admitCandidateToken())
        _ = window.candidateHellosCompleted(currentToken)

        let outcome = window.submitPairRequest(staleToken, proof: Data([9]))

        #expect(outcome == .rejected)
        #expect(verifier.callCount == 0)
        #expect(window.candidateInFlight)
        #expect(window.attemptsRemaining == 2)
    }

    private static func makeWindow(
        clock: ManualTestClock,
        verifier: any PairRequestVerifier
    ) -> (window: PairingWindow, clock: ManualTestClock) {
        let window = PairingWindow(dateProvider: FixedDateProvider(clock: clock).provider, proofVerifier: verifier)
        return (window, clock)
    }

    private static func makeWindow(
        clock: ManualTestClock,
        verifierResult: Bool = true
    ) -> (window: PairingWindow, clock: ManualTestClock) {
        makeWindow(clock: clock, verifier: SpyPairRequestVerifier(result: verifierResult))
    }
}
