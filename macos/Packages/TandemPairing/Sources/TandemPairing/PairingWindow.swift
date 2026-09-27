import Foundation
import TandemTransport

/// Wall-clock time seam, matching `TandemTestSupport.DateProvider`'s underlying closure type
/// structurally so tests can bridge a `ManualTestClock` in via `FixedDateProvider` without this
/// main target depending on that test-support package (E00-24; `TandemTestSupport` is a
/// test-target-only dependency, `tools/lint/swift-package-rules.rb`).
public typealias DateProvider = @Sendable () -> Date

/// Why a pairing window closed (`docs/protocol/SPEC.md` § Pairing window). `nil` (via
/// ``PairingWindow/closedReason``) means the window has never been opened yet.
public enum PairingWindowClosedReason: Sendable, Equatable {
    /// The owner clicked Pair on the confirmation dialog (`PairAccepted`).
    case paired
    /// 120 s elapsed since opening with no successful pairing.
    case expired
    /// A 3rd attempt was just burned (by a bad proof or a candidate closing before
    /// `PairAccepted`), leaving no attempts remaining.
    case attemptsExhausted
    /// Explicit owner cancel (e.g. closing the QR sheet).
    case cancelled
    /// Owner-initiated decline (Don't Pair / Escape / dismiss) of a confirmation dialog whose
    /// connection was still open (`docs/planning/decisions.md` D-73) -- destroys the secret and
    /// closes the whole window, the same as a successful pairing, rather than merely burning one
    /// attempt.
    case declined
}

/// Outcome of ``PairingWindow/submitPairRequest(_:proof:)``.
public enum PairRequestOutcome: Sendable, Equatable {
    /// The proof was valid; the candidate now waits on the owner's confirmation dialog
    /// (``PairingWindow/ownerAccepted(_:)``/``PairingWindow/ownerDeclined(_:)``).
    case pendingConfirmation
    /// The window wasn't open, no candidate was awaiting a request, or the proof was invalid.
    /// The caller has nothing further to do with this attempt.
    case rejected
}

/// The pairing-window state machine (E14-02, `docs/protocol/SPEC.md` § Pairing window). Conforms
/// to ``PairingWindowState`` (E12-02, `TandemTransport`) so `PeerAuthorizer` can claim/release the
/// single candidate slot through this same instance.
///
/// Time is settled lazily rather than by a background timer/Task: every public member first
/// reconciles `dateProvider()` against the window's 120 s expiry and, while a candidate is
/// admitted but hasn't yet sent `PairRequest`, its 10 s deadline (`docs/protocol/SPEC.md` § Frame
/// order, E01-22). Tests drive time purely by advancing a `ManualTestClock` the caller bridges
/// into `dateProvider` (`TandemTestSupport.FixedDateProvider`) and then reading any property or
/// calling any method -- no `Task`/`sleep` race to synchronize with.
public final class PairingWindow: PairingWindowState, @unchecked Sendable {

    public static let defaultExpiry: TimeInterval = 120
    public static let defaultCandidateRequestDeadline: TimeInterval = 10
    public static let defaultMaxAttempts = 3

    private enum CandidateState: Equatable {
        /// No candidate connection currently occupies the slot.
        case unclaimed
        /// Admitted (verify callback accepted the unknown certificate) but hellos not yet done.
        case admitted(PairingCandidateToken)
        /// Hellos completed; ``PairingWindow`` sent `PairChallenge` and is waiting up to 10 s for
        /// `PairRequest`.
        case awaitingRequest(PairingCandidateToken, helloCompletedAt: Date, challenge: Data)
        /// A valid proof was received; waiting on the owner's confirmation dialog.
        case confirmationPending(PairingCandidateToken, challenge: Data)

        /// The token that currently owns the slot (E14-16 finding #2), `nil` while ``unclaimed``.
        /// Every candidate-scoped call below is a no-op unless the token it's given matches this
        /// one, so a stale candidate can never mutate a different, currently-admitted candidate's
        /// state.
        var token: PairingCandidateToken? {
            switch self {
            case .unclaimed: return nil
            case .admitted(let tok), .awaitingRequest(let tok, _, _), .confirmationPending(let tok, _): return tok
            }
        }
    }

    private struct OpenState {
        let secretBox: SecretBox
        let expiresAt: Date
        var attemptsRemaining: Int
        var candidate: CandidateState
    }

    private enum Phase {
        case closed(PairingWindowClosedReason?, attemptsRemaining: Int)
        case open(OpenState)
    }

    private let dateProvider: DateProvider
    private let challengeSource: any ChallengeSource
    private let proofVerifier: any PairRequestVerifier
    private let expiry: TimeInterval
    private let candidateRequestDeadline: TimeInterval
    private let maxAttempts: Int

    private let lock = NSLock()
    private var phase: Phase = .closed(nil, attemptsRemaining: 0)

    public init(
        dateProvider: @escaping DateProvider,
        proofVerifier: any PairRequestVerifier,
        challengeSource: any ChallengeSource = SystemChallengeSource(),
        expiry: TimeInterval = PairingWindow.defaultExpiry,
        candidateRequestDeadline: TimeInterval = PairingWindow.defaultCandidateRequestDeadline,
        maxAttempts: Int = PairingWindow.defaultMaxAttempts
    ) {
        self.dateProvider = dateProvider
        self.proofVerifier = proofVerifier
        self.challengeSource = challengeSource
        self.expiry = expiry
        self.candidateRequestDeadline = candidateRequestDeadline
        self.maxAttempts = maxAttempts
    }

    // MARK: - Opening / closing

    /// Opens a fresh window with `secret` -- E14-01 generates this once so the identical value
    /// also encodes the QR `s` field -- zeroing and discarding any previous secret first.
    /// Regenerating always invalidates the previous window, even mid-candidate: any admitted
    /// candidate's slot is dropped without burning an attempt (it belonged to the window that no
    /// longer exists).
    public func open(secret: Data) {
        lock.lock()
        defer { lock.unlock() }
        if case .open(let previous) = phase {
            previous.secretBox.zero()
        }
        let expiresAt = dateProvider().addingTimeInterval(expiry)
        phase = .open(
            OpenState(
                secretBox: SecretBox(secret),
                expiresAt: expiresAt,
                attemptsRemaining: maxAttempts,
                candidate: .unclaimed
            )
        )
    }

    /// Explicit owner cancel (e.g. closing the QR sheet before any pairing completes).
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        closeLocked(.cancelled)
    }

    // MARK: - PairingWindowState

    public var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        if case .open = phase { return true }
        return false
    }

    /// Atomic test-and-set claim of the single candidate slot (D-18, `PairingWindowState`
    /// conformance for ``PeerAuthorizer``, E12-02): succeeds only if the window is open and no
    /// other candidate is already in flight, returning a fresh ``PairingCandidateToken`` that
    /// scopes every later call for this one candidate.
    public func admitCandidate() -> PairingCandidateToken? {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        guard case .open(var state) = phase, state.candidate == .unclaimed else { return nil }
        let token = PairingCandidateToken()
        state.candidate = .admitted(token)
        phase = .open(state)
        return token
    }

    /// Frees the slot a prior ``admitCandidate()`` call claimed, called by the candidate
    /// connection's own lifecycle handling once it closes for any reason before `PairAccepted`.
    /// Burns exactly one attempt (`docs/planning/decisions.md` D-70) -- regardless of which of the
    /// candidate's sub-states it was in (admitted only, awaiting a request, or a confirmation
    /// dialog pending) -- unless `token` no longer names the current candidate (the slot is already
    /// free -- e.g. the attempt was already burned by the 10 s timeout -- the window already closed
    /// via ``ownerAccepted(_:)``/``ownerDeclined(_:)``, or it has since been regenerated or claimed
    /// by a different candidate, E14-16 finding #2), in which case this is a no-op.
    public func releaseCandidate(_ token: PairingCandidateToken) {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        guard case .open(var state) = phase, state.candidate.token == token else { return }
        state.candidate = .unclaimed
        burnAttempt(&state)
    }

    /// Called only by the active 10 s `PairRequest` deadline watcher (E14-16 finding #5,
    /// `docs/protocol/SPEC.md` §10 "`PairRequest` deadline"): frees the slot and burns one attempt
    /// only if `token` is still the current candidate *and* it is still exactly
    /// ``CandidateState/awaitingRequest`` -- a no-op if a `PairRequest` (valid or not) already
    /// moved it past that sub-state, or the slot was freed some other way first, so a timer firing
    /// after the real deadline was already superseded can never re-burn or re-release a candidate
    /// that has moved on. Returns whether it actually did so, so the caller knows whether to close
    /// the connection (local reason `TIMEOUT`, no `PairRejected` sent, `docs/planning/decisions.md`
    /// D-72).
    @discardableResult
    public func requestDeadlineElapsed(_ token: PairingCandidateToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Checked *before* `settleLocked()`, unlike every other method here: that call performs
        // this exact "is `token` still `.awaitingRequest` past its 10s deadline" check itself, as
        // a side effect of every other locked call -- and since this method's only caller (the
        // active watcher in `PairingCoordinator`) calls it right after its own equivalent
        // `clock.sleep(for:)` elapses, `settleLocked()` would otherwise always win that race:
        // silently freeing the slot and burning the attempt first, so a guard checked *after*
        // settling never observes `.awaitingRequest` and this method reports `false` for the exact
        // case it exists to detect. That leaves `PairingCandidateFlow` never told to close the
        // connection -- a real deadlock (the frame loop parks on `frames.next()` forever), not
        // merely a burned attempt.
        guard case .open(var state) = phase, case .awaitingRequest = state.candidate, state.candidate.token == token
        else {
            settleLocked()
            return false
        }
        state.candidate = .unclaimed
        burnAttempt(&state)
        return true
    }

    // MARK: - Candidate lifecycle

    /// Called once both sides' `VersionHello` exchange completes on the admitted candidate
    /// connection. Generates and stores this candidate's `PairChallenge` (`cb`, D-67) and starts
    /// its 10 s `PairRequest` deadline. Returns `nil` if `token` no longer names a currently
    /// `.admitted` candidate (wrong call order, the window closed/regenerated first, or this token
    /// belongs to a candidate that has since been superseded, E14-16 finding #2).
    public func candidateHellosCompleted(_ token: PairingCandidateToken) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        guard case .open(var state) = phase, case .admitted = state.candidate, state.candidate.token == token else {
            return nil
        }
        let challenge = challengeSource.generateChallenge()
        state.candidate = .awaitingRequest(token, helloCompletedAt: dateProvider(), challenge: challenge)
        phase = .open(state)
        return challenge
    }

    /// A `Heartbeat` on a pairing-candidate connection is never a pairing failure, at any point --
    /// including while a confirmation dialog is pending (`docs/planning/decisions.md` D-69,
    /// `docs/protocol/SPEC.md` § Frame order). Intentionally a no-op beyond settling elapsed time:
    /// it neither resets the 10 s `PairRequest` deadline nor touches the attempt budget.
    public func heartbeatReceived() {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
    }

    /// Evaluates a received `PairRequest.proof` against this candidate's stored secret and
    /// challenge. A window that's closed, or `token` no longer matching a candidate currently
    /// ``awaitingRequest`` (already timed out, never reached that state, or already resolved), is
    /// rejected without ever invoking ``PairRequestVerifier``. A valid proof moves the candidate to
    /// awaiting the owner's confirmation and burns nothing; an invalid proof burns one attempt and
    /// frees the slot immediately.
    public func submitPairRequest(_ token: PairingCandidateToken, proof: Data) -> PairRequestOutcome {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        guard case .open(var state) = phase,
              state.candidate.token == token,
              case .awaitingRequest(_, _, let challenge) = state.candidate
        else {
            return .rejected
        }

        guard proofVerifier.verify(proof: proof, secret: state.secretBox.data, challenge: challenge) else {
            state.candidate = .unclaimed
            burnAttempt(&state)
            return .rejected
        }

        state.candidate = .confirmationPending(token, challenge: challenge)
        phase = .open(state)
        return .pendingConfirmation
    }

    /// The owner clicked Pair on the confirmation dialog. Closes the window as ``paired``&nbsp;--
    /// single-use, the secret is destroyed and never reused for a second phone -- and is a no-op
    /// (returns `false`) if no confirmation is currently pending for `token` (e.g. it was already
    /// resolved, the candidate connection already dropped and freed the slot per D-73's "commits
    /// nothing" rule, the window expired while the dialog was showing, or `token` belongs to a
    /// candidate this window has since superseded, E14-16 finding #2). Returns `true` only if this
    /// call actually committed the ``paired`` transition -- callers (E14-08) MUST NOT treat trust
    /// as committed, nor send `PairAccepted`, unless this is `true` (finding #3).
    @discardableResult
    public func ownerAccepted(_ token: PairingCandidateToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        guard case .open(let state) = phase,
              case .confirmationPending = state.candidate,
              state.candidate.token == token
        else {
            return false
        }
        let attemptsRemaining = state.attemptsRemaining
        state.secretBox.zero()
        phase = .closed(.paired, attemptsRemaining: attemptsRemaining)
        return true
    }

    /// An owner-initiated decline (Don't Pair, Escape, or dismiss) of a confirmation dialog whose
    /// connection is still open. Closes the *entire* window (`docs/planning/decisions.md` D-73),
    /// destroying the secret -- distinct from ``releaseCandidate(_:)``, which only burns one
    /// attempt and leaves the window open. A no-op if no confirmation is currently pending for
    /// `token` (the connection already dropped first and ``releaseCandidate(_:)`` already ran the
    /// D-70 attempt burn, or `token` no longer names the current candidate; this stale click
    /// commits nothing and decrements nothing a second time).
    public func ownerDeclined(_ token: PairingCandidateToken) {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        guard case .open(let state) = phase,
              case .confirmationPending = state.candidate,
              state.candidate.token == token
        else {
            return
        }
        let attemptsRemaining = state.attemptsRemaining
        state.secretBox.zero()
        phase = .closed(.declined, attemptsRemaining: attemptsRemaining)
    }

    // MARK: - Introspection

    /// `nil` while open or never opened; the reason once closed.
    public var closedReason: PairingWindowClosedReason? {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        if case .closed(let reason, _) = phase { return reason }
        return nil
    }

    /// Attempts left in the current (or just-closed) window; `0` once ``attemptsExhausted``.
    public var attemptsRemaining: Int {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        switch phase {
        case .open(let state): return state.attemptsRemaining
        case .closed(_, let attemptsRemaining): return attemptsRemaining
        }
    }

    /// `true` whenever the single candidate slot (D-18) is occupied, in any of its sub-states.
    public var candidateInFlight: Bool {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        if case .open(let state) = phase { return state.candidate != .unclaimed }
        return false
    }

    /// `true` only while a valid proof has been received and the owner's confirmation dialog is
    /// the one thing standing between this candidate and `PairAccepted`.
    public var isConfirmationPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        if case .open(let state) = phase, case .confirmationPending = state.candidate { return true }
        return false
    }

    /// `nil` while closed; the 120 s expiry deadline while open.
    public var expiresAt: Date? {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        if case .open(let state) = phase { return state.expiresAt }
        return nil
    }

    /// The live secret box while open, `nil` once closed -- invariant 6. Not part of the public
    /// seam surface; exposed for this package's own tests (`@testable import`) to hold the exact
    /// same reference the window scrubs in place, so a test can verify the bytes are actually
    /// zeroed rather than merely unreachable.
    var secretBoxForTesting: SecretBox? {
        lock.lock()
        defer { lock.unlock() }
        if case .open(let state) = phase { return state.secretBox }
        return nil
    }

    // MARK: - Private

    /// Reconciles `dateProvider()` against the window's 120 s expiry and, failing that, an
    /// in-flight candidate's 10 s `PairRequest` deadline. Assumes `lock` is held.
    private func settleLocked() {
        guard case .open(var state) = phase else { return }
        let now = dateProvider()

        if now >= state.expiresAt {
            state.secretBox.zero()
            phase = .closed(.expired, attemptsRemaining: state.attemptsRemaining)
            return
        }

        if case .awaitingRequest(_, let helloCompletedAt, _) = state.candidate,
           now >= helloCompletedAt.addingTimeInterval(candidateRequestDeadline) {
            state.candidate = .unclaimed
            burnAttempt(&state)
            return
        }

        phase = .open(state)
    }

    /// Decrements `state.attemptsRemaining` by exactly one, closing the window as
    /// ``attemptsExhausted`` if that reaches zero, else writing `state` back as still open. Assumes
    /// `lock` is held and `state.candidate` has already been freed by the caller.
    private func burnAttempt(_ state: inout OpenState) {
        state.attemptsRemaining -= 1
        if state.attemptsRemaining <= 0 {
            state.secretBox.zero()
            phase = .closed(.attemptsExhausted, attemptsRemaining: 0)
        } else {
            phase = .open(state)
        }
    }

    /// Closes the window with `reason` if it's currently open (no-op if already closed). Assumes
    /// `lock` is held.
    private func closeLocked(_ reason: PairingWindowClosedReason) {
        guard case .open(let state) = phase else { return }
        let attemptsRemaining = state.attemptsRemaining
        state.secretBox.zero()
        phase = .closed(reason, attemptsRemaining: attemptsRemaining)
    }
}
