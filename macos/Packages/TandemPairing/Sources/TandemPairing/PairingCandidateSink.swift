import Foundation

/// The two wire values `PairRejected.reason` ever actually carries (`docs/protocol/SPEC.md` §2
/// "`PairRejected` wire collapse", `docs/planning/decisions.md` D-72): every local rejection
/// reason other than an owner decline collapses onto ``pairingUnavailable``. The fifth local
/// reason, `TIMEOUT`, sends no `PairRejected` at all, so it has no case here.
public enum PairRejectedWireReason: Sendable, Equatable {
    /// The owner explicitly declined the confirmation dialog (E14-08's concern, not this
    /// package's ``PairingCandidateFlow``).
    case rejectedByOwner
    /// Every other local rejection reason this candidate connection can produce: an expired
    /// window, a bad proof, or a malformed `PairRequest`.
    case pairingUnavailable
}

/// The wire-facing actions a pairing-candidate connection's flow handler (``PairingCandidateFlow``,
/// E14-09) needs from that connection: sending the two pairing-only outbound messages and closing
/// it. Deliberately narrow -- like ``PairRequestVerifier`` -- so the flow handler is unit-testable
/// without a real transport session (`TandemSession`, E12-12, not yet built) or a real socket.
public protocol PairingCandidateSink: Sendable {
    /// Sends `PairChallenge { challenge }` as the very next `CONTROL` frame
    /// (`docs/protocol/SPEC.md` §2 "Frame order on a pairing-candidate connection").
    func sendPairChallenge(_ challenge: Data) async throws

    /// Sends `PairRejected { reason }`, immediately before the connection closes
    /// (`docs/protocol/SPEC.md` §2 "`PairRejected` wire collapse").
    func sendPairRejected(_ reason: PairRejectedWireReason) async throws

    /// Closes the connection with the `PAIRING_FAILED` close code (`docs/protocol/SPEC.md` §5).
    func closePairingFailed() async
}
