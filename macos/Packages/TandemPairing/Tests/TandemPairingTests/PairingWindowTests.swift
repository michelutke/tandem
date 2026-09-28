import Foundation
import Testing
import TandemTestSupport
import TandemTransport
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
    func pairingWindow_failedAttempt_attemptsRemainingDecrementsByOne() throws {
        let window = Self.makeWindow(clock: ManualTestClock(), verifierResult: false).window

        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        let outcome = window.submitPairRequest(token, proof: Data([9]))

        #expect(outcome == .rejected)
        #expect(window.attemptsRemaining == 2)
        #expect(window.isOpen)
        #expect(!window.candidateInFlight)
    }

    @Test
    func pairingWindow_fourthAttempt_rejectedWithoutProofCheck() throws {
        let verifier = SpyPairRequestVerifier(result: false)
        let window = Self.makeWindow(clock: ManualTestClock(), verifier: verifier).window
        window.open(secret: Data([1]))

        var lastToken: PairingCandidateToken!
        for _ in 0..<3 {
            let token = try #require(window.admitCandidate())
            lastToken = token
            _ = window.candidateHellosCompleted(token)
            _ = window.submitPairRequest(token, proof: Data([9]))
        }

        #expect(window.closedReason == .attemptsExhausted)
        #expect(verifier.callCount == 3)

        // The last real candidate's own token is also stale now the window has closed.
        let outcome = window.submitPairRequest(lastToken, proof: Data([9]))

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
    func pairingWindow_successfulPairing_closedAndSecretCleared() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)

        #expect(window.ownerAccepted(token))

        #expect(!window.isOpen)
        #expect(window.closedReason == .paired)
        #expect(window.secretBoxForTesting == nil)
    }

    @Test
    func pairingWindow_sameSecretAfterSuccess_secondRequestRejected() throws {
        let verifier = SpyPairRequestVerifier(result: true)
        let window = Self.makeWindow(clock: ManualTestClock(), verifier: verifier).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        #expect(window.ownerAccepted(token))

        let callsBeforeSecondAttempt = verifier.callCount
        let outcome = window.submitPairRequest(token, proof: Data([9]))

        #expect(outcome == .rejected)
        #expect(verifier.callCount == callsBeforeSecondAttempt)
    }

    @Test
    func pairingWindow_regenerate_oldSecretProofRejected() throws {
        let clock = ManualTestClock()
        let secretA = Data([0xAA])
        let secretB = Data([0xBB])
        let window = PairingWindow(
            dateProvider: FixedDateProvider(clock: clock).provider,
            proofVerifier: SecretEqualityPairRequestVerifier(expectedSecret: secretA)
        )

        window.open(secret: secretA)
        window.open(secret: secretB)

        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        let outcome = window.submitPairRequest(token, proof: Data([9]))

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
        #expect(window.secretBoxForTesting == nil)
    }

    @Test
    func pairingWindow_candidateInFlight_secondCandidateRejectedNoAttemptBurned() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))

        _ = try #require(window.admitCandidate())
        #expect(window.candidateInFlight)
        #expect(window.admitCandidate() == nil)
        #expect(window.attemptsRemaining == 3)
    }

    @Test
    func pairingWindow_candidateSilentFor10s_closedAndOneAttemptBurned() throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)

        clock.advance(by: .seconds(10))

        #expect(!window.candidateInFlight)
        #expect(window.attemptsRemaining == 2)
        #expect(window.isOpen)
    }

    /// Regression: `requestDeadlineElapsed(_:)` is `PairingCoordinator`'s active watcher's only
    /// signal to close the actual connection -- if some *other* locked call (here, `isOpen`,
    /// standing in for a second connection's `PeerAuthorizer.decide` or a `Heartbeat`) happens to
    /// settle the same 10s deadline first, the watcher's own call must still report `.burned`, or
    /// its caller wrongly concludes "already handled" and never closes the connection (a real
    /// deadlock: the frame loop parks on `frames.next()` forever).
    @Test
    func pairingWindow_otherCallSettlesDeadlineFirst_requestDeadlineElapsedStillReportsBurned() throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)

        clock.advance(by: .seconds(10))
        _ = window.isOpen // forces settleLocked() to burn the deadline before the watcher checks in

        #expect(window.requestDeadlineElapsed(token) == .burned)
        #expect(window.attemptsRemaining == 2 && window.isOpen)
    }

    @Test
    func pairingCandidate_heartbeatWhileConfirmationPending_notAPairingFailure() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)

        window.heartbeatReceived()
        window.heartbeatReceived()

        #expect(window.isOpen)
        #expect(window.isConfirmationPending)
        #expect(window.attemptsRemaining == 3)
    }

    @Test
    func pairingWindow_candidateClosesBeforeHellos_burnsOneAttempt() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())

        window.releaseCandidate(token)

        #expect(window.attemptsRemaining == 2)
        #expect(!window.candidateInFlight)
        #expect(window.isOpen)
    }

    @Test
    func pairingWindow_peerClosesAfterChallenge_burnsOneAttempt() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)

        window.releaseCandidate(token)

        #expect(window.attemptsRemaining == 2)
        #expect(!window.candidateInFlight)
        #expect(window.isOpen)
    }

    @Test
    func pairingWindow_candidateDropsWhileDialogPending_attemptBurnedWindowStaysOpen() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)

        window.releaseCandidate(token)

        #expect(window.attemptsRemaining == 2)
        #expect(window.isOpen)
        #expect(!window.candidateInFlight)
        #expect(!window.isConfirmationPending)
    }

    @Test
    func pairingWindow_ownerDeclinesConfirmation_closedDeclinedSecretDestroyed() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)

        window.ownerDeclined(token)

        #expect(!window.isOpen)
        #expect(window.closedReason == .declined)
        #expect(window.secretBoxForTesting == nil)

        // A stale connection teardown after the fact (D-73) commits/decrements nothing again.
        let attemptsAfterDecline = window.attemptsRemaining
        window.releaseCandidate(token)
        #expect(window.attemptsRemaining == attemptsAfterDecline)
        #expect(window.closedReason == .declined)
    }

    // MARK: - E14-16 finding #2: generation-token scoping

    @Test
    func pairingWindow_staleCandidateReleaseAfterFreshAdmitted_freshCandidateUnaffected() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let staleToken = try #require(window.admitCandidate())

        // The stale candidate times out on its own (D-70 burn), freeing the slot for a fresh one.
        window.releaseCandidate(staleToken)
        #expect(window.attemptsRemaining == 2)

        let freshToken = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(freshToken)
        #expect(window.submitPairRequest(freshToken, proof: Data([9])) == .pendingConfirmation)

        // A delayed teardown task for the *stale* candidate, still holding its own (superseded)
        // token, must never touch the fresh candidate now occupying the slot.
        window.releaseCandidate(staleToken)

        #expect(window.isConfirmationPending)
        #expect(window.candidateInFlight)
        #expect(window.attemptsRemaining == 2)
    }

    @Test
    func pairingWindow_staleCandidateSubmitProofAfterFreshAdmitted_freshCandidateUnaffected() throws {
        let verifier = SpyPairRequestVerifier(result: true)
        let window = Self.makeWindow(clock: ManualTestClock(), verifier: verifier).window
        window.open(secret: Data([1]))
        let staleToken = try #require(window.admitCandidate())
        window.releaseCandidate(staleToken)
        let attemptsAfterStaleRelease = window.attemptsRemaining

        let freshToken = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(freshToken)

        // A late-arriving frame on the stale (already-closed) connection must be rejected --
        // without ever invoking `PairRequestVerifier` -- and without affecting the fresh
        // candidate's own budget or state.
        #expect(window.submitPairRequest(staleToken, proof: Data([9])) == .rejected)
        #expect(verifier.callCount == 0)
        #expect(window.attemptsRemaining == attemptsAfterStaleRelease)
        #expect(window.candidateInFlight)
    }

    @Test
    func pairingWindow_regenerateInvalidatesToken_oldTokenNoLongerReleasesNewSlot() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let firstWindowToken = try #require(window.admitCandidate())

        window.open(secret: Data([2]))
        let secondWindowToken = try #require(window.admitCandidate())

        window.releaseCandidate(firstWindowToken)

        #expect(window.candidateInFlight)
        #expect(window.attemptsRemaining == 3)

        window.releaseCandidate(secondWindowToken)
        #expect(!window.candidateInFlight)
        #expect(window.attemptsRemaining == 2)
    }
}
