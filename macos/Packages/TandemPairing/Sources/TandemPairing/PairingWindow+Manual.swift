import Foundation
import TandemTransport

/// Manual-pairing members of ``PairingWindow`` (E73-04, ADR-008): the same single-candidate slot,
/// 120 s expiry and 3-attempt budget as a QR window, with a different message sequence.
extension PairingWindow {
    /// The mode the current (or most recently closed) window was opened in.
    public var mode: PairingMode {
        lock.lock()
        defer { lock.unlock() }
        return currentMode
    }

    /// Opens a fresh manual-mode window, zeroing and discarding any previous one. There is no
    /// pairing secret: the SAS comparison is the only authenticator, so the secret slot stays empty.
    public func openManual() {
        lock.lock()
        defer { lock.unlock() }
        openLocked(secret: Data(), mode: .manual)
    }

    /// The phone's `Commitment` arrived on `token`'s candidate and the Mac is about to answer with its
    /// own. `true` only on a manual window while that candidate is awaiting its first message (inside
    /// its 10 s deadline); the caller fails the candidate on `false`, which burns the attempt.
    public func manualCommitmentReceived(_ token: PairingCandidateToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        guard currentMode == .manual,
              case .open(var state) = phase,
              case .awaitingRequest(_, _, let challenge) = state.candidate,
              state.candidate.token == token
        else {
            return false
        }
        state.candidate = .manualInProgress(token, challenge: challenge)
        phase = .open(state)
        return true
    }

    /// The phone's `Reveal` verified against its `Commitment`: the candidate now waits on the owner's
    /// confirmation dialog, exactly like a valid QR proof. `false` if `token` isn't mid-handshake.
    public func manualRevealVerified(_ token: PairingCandidateToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        settleLocked()
        guard case .open(var state) = phase,
              case .manualInProgress(_, let challenge) = state.candidate,
              state.candidate.token == token
        else {
            return false
        }
        state.candidate = .confirmationPending(token, challenge: challenge)
        phase = .open(state)
        return true
    }
}
