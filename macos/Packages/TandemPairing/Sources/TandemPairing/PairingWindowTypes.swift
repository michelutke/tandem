import Foundation
import TandemTransport

/// Outcome of ``PairingWindow/requestDeadlineElapsed(_:)`` (E14-25), resolved under a single lock
/// acquisition so the caller never has to reconcile two separately-locked calls itself. Lives here,
/// not `PairingWindow.swift`, only to keep that file within the lint file-length bound -- it's
/// public API like ``PairRequestOutcome``, not one of the `internal` state types below.
public enum PairingCandidateDeadlineOutcome: Sendable, Equatable {
    /// This call itself observed `token`'s candidate still `awaitingRequest` past its 10 s
    /// deadline and burned the attempt.
    case burned
    /// Some other locked call already freed `token` out of the slot for a reason other than this
    /// exact candidate pairing successfully -- already burned by another path, the window's own
    /// 120 s whole-window expiry, or a fresher candidate has since superseded `token`.
    case gone
    /// `token` still owns the slot in an open window, or the window closed specifically because
    /// this exact candidate's own pairing just succeeded (`.paired`, the same exclusion E14-16
    /// finding #4 applies to ``PairingCandidateFlow/heartbeatReceived()``) -- the caller must not
    /// close.
    case stillInFlight
}

/// ``PairingWindow`` members split out to keep that file within the file/type-length lint bounds.
extension PairingWindow {
    /// Called only by the active 10 s `PairRequest` deadline watcher (E14-16 finding #5,
    /// `docs/protocol/SPEC.md` §10 "`PairRequest` deadline"): frees the slot and burns one attempt
    /// for `token`'s candidate if a `PairRequest` hasn't already moved it past
    /// ``CandidateState/awaitingRequest``, and reports a ``PairingCandidateDeadlineOutcome`` under
    /// this same lock acquisition -- replacing the previous `Bool` plus a separate scoped
    /// `candidateInFlight(_:)` check, whose two separate lock acquisitions let a confirmed
    /// `PairRequest` in between move `token` to `.closed(.paired)` unnoticed (E14-25).
    public func requestDeadlineElapsed(_ token: PairingCandidateToken) -> PairingCandidateDeadlineOutcome {
        lock.lock()
        defer { lock.unlock() }

        // Checked before settleLocked(): watcher is first to check in, token still awaitingRequest.
        if case .open(var state) = phase, case .awaitingRequest = state.candidate, state.candidate.token == token {
            state.candidate = .unclaimed
            burnAttempt(&state)
            return .burned
        }

        // Otherwise some other locked call ran settleLocked() first and burned this token as a
        // side effect -- deadlineBurnedToken lets this still report .burned, not "already handled".
        settleLocked()
        if deadlineBurnedToken == token {
            deadlineBurnedToken = nil
            return .burned
        }

        switch phase {
        case .open(let state):
            return state.candidate.token == token ? .stillInFlight : .gone
        case .closed(.paired, _):
            // Scoped to the token that actually paired (E14-25 fix #2): an earlier candidate
            // whose slot was dropped by a regenerate must still report .gone even though the
            // window is now .closed(.paired) from a *different*, later candidate pairing.
            return pairedToken == token ? .stillInFlight : .gone
        case .closed:
            return .gone
        }
    }

    // Internal (not private) state types, only because they now live in a separate file -- nothing
    // outside `TandemPairing` sees them, since `PairingWindow`'s own public surface never exposes
    // them.

    enum CandidateState: Equatable {
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

    struct OpenState {
        let secretBox: SecretBox
        let expiresAt: Date
        var attemptsRemaining: Int
        var candidate: CandidateState
    }

    enum Phase {
        case closed(PairingWindowClosedReason?, attemptsRemaining: Int)
        case open(OpenState)
    }
}
