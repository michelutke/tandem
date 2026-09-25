import Foundation
import Testing
import TandemTestSupport
@testable import TandemPairing

/// The pairing-window state machine (E14-02, `docs/protocol/SPEC.md` § Pairing window). Time is
/// driven purely by a `ManualTestClock` bridged into a `DateProvider` via `FixedDateProvider` --
/// `PairingWindow` settles elapsed time lazily on every call, so there's no `Task`/`sleep` race to
/// synchronize with (contrast `ManualTestClockTests`, which drives a real async sleeper).
@Suite("PairingWindow")
struct PairingWindowTests {

    @Test
    func pairingWindow_open_threeAttemptsAndExpiresIn120s() {
        let clock = ManualTestClock()
        let dateProvider = FixedDateProvider(clock: clock).provider
        let window = PairingWindow(dateProvider: dateProvider, proofVerifier: SpyPairRequestVerifier(result: true))

        window.open(secret: Data([1, 2, 3]))

        #expect(window.isOpen)
        #expect(window.attemptsRemaining == 3)
        #expect(window.expiresAt == dateProvider().addingTimeInterval(120))
    }

    @Test
    func pairingWindow_failedAttempt_attemptsRemainingDecrementsByOne() {
        let window = Self.makeWindow(clock: ManualTestClock(), verifierResult: false).window

        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        #expect(window.candidateHellosCompleted() != nil)
        let outcome = window.submitPairRequest(proof: Data([9]))

        #expect(outcome == .rejected)
        #expect(window.attemptsRemaining == 2)
        #expect(window.isOpen)
        #expect(!window.candidateInFlight)
    }

    @Test
    func pairingWindow_fourthAttempt_rejectedWithoutProofCheck() {
        let verifier = SpyPairRequestVerifier(result: false)
        let window = Self.makeWindow(clock: ManualTestClock(), verifier: verifier).window
        window.open(secret: Data([1]))

        for _ in 0..<3 {
            #expect(window.admitCandidate())
            _ = window.candidateHellosCompleted()
            _ = window.submitPairRequest(proof: Data([9]))
        }

        #expect(window.closedReason == .attemptsExhausted)
        #expect(verifier.callCount == 3)

        let outcome = window.submitPairRequest(proof: Data([9]))

        #expect(outcome == .rejected)
        #expect(verifier.callCount == 3)
    }

    @Test
    func pairingWindow_advance119s_stillOpen() {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock).window
        window.open(secret: Data([1]))

        clock.advance(by: .seconds(119))

        #expect(window.isOpen)
    }

    @Test
    func pairingWindow_advance120sNoAttempts_closedExpired() {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock).window
        window.open(secret: Data([1]))

        clock.advance(by: .seconds(120))

        #expect(!window.isOpen)
        #expect(window.closedReason == .expired)
        #expect(window.attemptsRemaining == 3)
    }

    @Test
    func pairingWindow_successfulPairing_closedAndSecretCleared() {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        _ = window.candidateHellosCompleted()
        #expect(window.submitPairRequest(proof: Data([9])) == .pendingConfirmation)

        window.ownerAccepted()

        #expect(!window.isOpen)
        #expect(window.closedReason == .paired)
        #expect(window.secretForTesting == nil)
    }

    @Test
    func pairingWindow_sameSecretAfterSuccess_secondRequestRejected() {
        let verifier = SpyPairRequestVerifier(result: true)
        let window = Self.makeWindow(clock: ManualTestClock(), verifier: verifier).window
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        _ = window.candidateHellosCompleted()
        #expect(window.submitPairRequest(proof: Data([9])) == .pendingConfirmation)
        window.ownerAccepted()

        let callsBeforeSecondAttempt = verifier.callCount
        let outcome = window.submitPairRequest(proof: Data([9]))

        #expect(outcome == .rejected)
        #expect(verifier.callCount == callsBeforeSecondAttempt)
    }

    @Test
    func pairingWindow_regenerate_oldSecretProofRejected() {
        let clock = ManualTestClock()
        let secretA = Data([0xAA])
        let secretB = Data([0xBB])
        let window = PairingWindow(
            dateProvider: FixedDateProvider(clock: clock).provider,
            proofVerifier: SecretEqualityPairRequestVerifier(expectedSecret: secretA)
        )

        window.open(secret: secretA)
        window.open(secret: secretB)

        #expect(window.admitCandidate())
        _ = window.candidateHellosCompleted()
        let outcome = window.submitPairRequest(proof: Data([9]))

        #expect(outcome == .rejected)
        #expect(window.attemptsRemaining == 2)
    }

    @Test
    func pairingWindow_explicitCancel_closedCancelled() {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))

        window.cancel()

        #expect(!window.isOpen)
        #expect(window.closedReason == .cancelled)
        #expect(window.secretForTesting == nil)
    }

    @Test
    func pairingWindow_candidateInFlight_secondCandidateRejectedNoAttemptBurned() {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))

        #expect(window.admitCandidate())
        #expect(window.candidateInFlight)
        #expect(!window.admitCandidate())
        #expect(window.attemptsRemaining == 3)
    }

    @Test
    func pairingWindow_candidateSilentFor10s_closedAndOneAttemptBurned() {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock).window
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        #expect(window.candidateHellosCompleted() != nil)

        clock.advance(by: .seconds(10))

        #expect(!window.candidateInFlight)
        #expect(window.attemptsRemaining == 2)
        #expect(window.isOpen)
    }

    @Test
    func pairingCandidate_heartbeatWhileConfirmationPending_notAPairingFailure() {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        _ = window.candidateHellosCompleted()
        #expect(window.submitPairRequest(proof: Data([9])) == .pendingConfirmation)

        window.heartbeatReceived()
        window.heartbeatReceived()

        #expect(window.isOpen)
        #expect(window.isConfirmationPending)
        #expect(window.attemptsRemaining == 3)
    }

    @Test
    func pairingWindow_candidateClosesBeforeHellos_burnsOneAttempt() {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())

        window.releaseCandidate()

        #expect(window.attemptsRemaining == 2)
        #expect(!window.candidateInFlight)
        #expect(window.isOpen)
    }

    @Test
    func pairingWindow_peerClosesAfterChallenge_burnsOneAttempt() {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        #expect(window.candidateHellosCompleted() != nil)

        window.releaseCandidate()

        #expect(window.attemptsRemaining == 2)
        #expect(!window.candidateInFlight)
        #expect(window.isOpen)
    }

    @Test
    func pairingWindow_candidateDropsWhileDialogPending_attemptBurnedWindowStaysOpen() {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        _ = window.candidateHellosCompleted()
        #expect(window.submitPairRequest(proof: Data([9])) == .pendingConfirmation)

        window.releaseCandidate()

        #expect(window.attemptsRemaining == 2)
        #expect(window.isOpen)
        #expect(!window.candidateInFlight)
        #expect(!window.isConfirmationPending)
    }

    @Test
    func pairingWindow_ownerDeclinesConfirmation_closedDeclinedSecretDestroyed() {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        #expect(window.admitCandidate())
        _ = window.candidateHellosCompleted()
        #expect(window.submitPairRequest(proof: Data([9])) == .pendingConfirmation)

        window.ownerDeclined()

        #expect(!window.isOpen)
        #expect(window.closedReason == .declined)
        #expect(window.secretForTesting == nil)

        // A stale connection teardown after the fact (D-73) commits/decrements nothing again.
        let attemptsAfterDecline = window.attemptsRemaining
        window.releaseCandidate()
        #expect(window.attemptsRemaining == attemptsAfterDecline)
        #expect(window.closedReason == .declined)
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
