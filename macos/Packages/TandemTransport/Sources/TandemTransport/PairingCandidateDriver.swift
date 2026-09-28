import Foundation
import TandemProtocol

/// The seam ``NWListenerFactory`` hands a `.pairingCandidate` connection to, once its
/// `VersionHello` exchange completes (`handshake.session == .ready`), instead of ever registering
/// it in a session registry (registration stays `.trusted`-only, E12-19). The actual pairing state
/// machine (`PairingWindow`, `PairingCandidateFlow`, E14-02/E14-09) lives in the higher-level
/// `TandemPairing` package, which already depends on this one (PRD module rules: transport depends
/// on protocol, never the reverse -- and pairing depends on transport, so transport may not depend
/// back on pairing); this protocol is the boundary a `TandemPairing` type crosses back in.
///
/// `NWListenerFactory` never calls this for a `.trusted` connection, and does nothing further with
/// `session` once a call to ``drive(session:handshakeSpkiDer:)`` returns -- the pairing dance
/// (including the owner's mutual-confirmation dialog) is this conformer's entire concern from
/// there.
public protocol PairingCandidateDriver: Sendable {
    /// - Parameters:
    ///   - session: This connection's already-`.ready` `TandemSession` (`VersionHello` exchanged
    ///     both ways).
    ///   - handshakeSpkiDer: The phone's SPKI DER exactly as ``PeerVerifier`` (E12-02) observed it
    ///     on this connection's own TLS handshake -- never re-derived, never trusted from any wire
    ///     field of a later message.
    ///   - token: The ``PairingCandidateToken`` this connection's verify-callback
    ///     ``PairingWindowState/admitCandidate()`` claim returned -- threaded through so every
    ///     window mutation this candidate's own pairing dance performs is scoped to it (E14-16
    ///     finding #2).
    func drive(session: any TandemSession, handshakeSpkiDer: Data, token: PairingCandidateToken) async

    /// Called instead of ``drive(session:handshakeSpkiDer:token:)`` when a `.pairingCandidate`
    /// connection never reaches the point of being handed off to it at all -- an ALPN mismatch, a
    /// failed/cancelled handshake, a `VersionHello` mismatch or timeout, or any other pre-`Ready`
    /// exit (E14-16 finding #1, `docs/planning/decisions.md` D-70: even a silent candidate still
    /// burns its one attempt and frees the slot). Releases exactly the slot `token` names, scoped
    /// so it can never affect a different candidate that has since claimed the slot (finding #2).
    func candidateAbandoned(token: PairingCandidateToken) async
}
