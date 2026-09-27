import Foundation
import TandemTransport

/// Private state types for ``PairingWindow``, split out to keep that file within the file/type-
/// length lint bounds. `internal` (not `private`) only because they now live in a separate file --
/// nothing outside `TandemPairing` sees them, since `PairingWindow`'s own public surface never
/// exposes them.
extension PairingWindow {
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
