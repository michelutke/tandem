import Foundation
import Testing
import TandemTestSupport
@testable import TandemPairing

/// ``PairingWindow/ownerAccepted(_:)``'s two edge cases (cycle 8 adversarial review, D-73): the
/// secret buffer is scrubbed in place, not merely dropped, and a window that expired while the
/// confirmation dialog was showing refuses the `.paired` transition instead of committing it late.
/// Split out of `PairingWindowTests` to keep both files under the project's type-body-length
/// limit -- the rest of the candidate-token safety net (a stale caller from a since-released or
/// since-replaced candidate can only ever no-op) is covered there
/// ("E14-16 finding #2: generation-token scoping").
@Suite("PairingWindow candidate tokens")
struct PairingWindowCandidateTokenTests {

    @Test
    func pairingWindow_ownerAccepted_secretBytesActuallyZeroed() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([0xAA, 0xBB, 0xCC]))
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        let box = try #require(window.secretBoxForTesting)

        #expect(window.ownerAccepted(token))

        // The literal same buffer `submitPairRequest` read from is scrubbed in place, not merely
        // dropped -- `secretBoxForTesting == nil` alone doesn't prove that.
        #expect(box.bytes.allSatisfy { $0 == 0 })
    }

    @Test
    func pairingWindow_ownerAccepted_windowExpiredWhileDialogPending_noOpReturnsFalse() throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)

        clock.advance(by: .seconds(120))

        #expect(!window.ownerAccepted(token))
        #expect(window.closedReason == .expired)
    }

    // MARK: - E14-25: atomic tri-state `requestDeadlineElapsed(_:)`, `.paired` exclusion

    /// Regression, replacing the two separately-locked calls (this method plus a scoped
    /// `candidateInFlight(_:)`) the pre-E14-25 fix used: a stale watcher whose own token has since
    /// been superseded by a fresh candidate (admitted after the stale one's slot was freed by some
    /// other path, so `deadlineBurnedToken` was never set for it) must resolve as `.gone` -- and,
    /// resolved under the single lock acquisition this call now makes, must never touch the fresh
    /// candidate's own slot while doing so.
    @Test
    func requestDeadlineElapsed_staleWatcherAfterFreshCandidateAdmitted_closesStaleOnlyNotFresh() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([1]))
        let staleToken = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(staleToken) != nil)

        // Freed by some path other than its own 10 s deadline (e.g. a peer disconnect), just like
        // the whole-window-expiry branch this bug class also covers: `deadlineBurnedToken` is never
        // set for `staleToken`.
        window.releaseCandidate(staleToken)
        let freshToken = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(freshToken) != nil)

        #expect(window.requestDeadlineElapsed(staleToken) == .gone)

        #expect(window.candidateInFlight, "the fresh candidate's slot must be untouched by the stale watcher")
    }

    /// The TOCTOU this fix closes (E14-25, a narrow follow-up to E14-16 finding #4's own `.paired`
    /// exclusion): a `PairRequest` accepted and confirmed between the watcher's old two separate
    /// lock acquisitions could move `token` all the way to `.closed(.paired)`, which the old,
    /// separately-locked `candidateInFlight(_:)` call alone couldn't tell apart from any other
    /// "no longer in flight" reason. Resolved under one lock now, `requestDeadlineElapsed(_:)` must
    /// report `.stillInFlight` -- never `.gone` -- once pairing has actually succeeded, so the
    /// caller never closes a session that just got trusted.
    @Test
    func requestDeadlineElapsed_windowAlreadyPaired_noOp() throws {
        let window = Self.makeWindow(clock: ManualTestClock(), verifierResult: true).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(token) != nil)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        #expect(window.ownerAccepted(token))

        #expect(window.requestDeadlineElapsed(token) == .stillInFlight)

        #expect(window.closedReason == .paired)
    }

    /// Fix #2 (E14-25 verifier finding): the `.paired` exclusion above must be scoped to the
    /// token that actually paired. A regenerate drops an earlier candidate's slot without burning
    /// its deadline watcher's token; if a *different*, later candidate then pairs, the earlier
    /// watcher's stale token must still resolve `.gone` even though the window itself now reads
    /// `.closed(.paired, _)` -- otherwise the stale watcher wrongly treats a slot it never
    /// occupied as still in flight and never closes.
    @Test
    func requestDeadlineElapsed_windowPairedByDifferentToken_staleTokenGone() throws {
        let window = Self.makeWindow(clock: ManualTestClock(), verifierResult: true).window
        window.open(secret: Data([1]))
        let staleToken = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(staleToken) != nil)

        window.open(secret: Data([2]))
        let freshToken = try #require(window.admitCandidate())
        #expect(window.candidateHellosCompleted(freshToken) != nil)
        #expect(window.submitPairRequest(freshToken, proof: Data([9])) == .pendingConfirmation)
        #expect(window.ownerAccepted(freshToken))

        #expect(window.requestDeadlineElapsed(staleToken) == .gone)
        #expect(window.requestDeadlineElapsed(freshToken) == .stillInFlight)
    }

    private static func makeWindow(
        clock: ManualTestClock,
        verifierResult: Bool = true
    ) -> (window: PairingWindow, clock: ManualTestClock) {
        let window = PairingWindow(
            dateProvider: FixedDateProvider(clock: clock).provider,
            proofVerifier: SpyPairRequestVerifier(result: verifierResult)
        )
        return (window, clock)
    }
}
