import Foundation
import TandemCrypto
import TandemTransport

/// The real ``PairRequestVerifier`` (E14-07, `docs/protocol/SPEC.md` §2 "Proof computation"):
/// recomputes the expected `proof` from the Mac's own SPKI, the phone SPKI actually observed on
/// this candidate connection's TLS handshake, and the candidate's own `PairChallenge` value
/// (`challenge`, D-67, held by ``PairingWindow`` and passed in as `PairRequestVerifier.verify`'s
/// `challenge` parameter) -- then compares against `PairRequest.proof` with an injected
/// constant-time ``ByteComparator`` (invariant 6). Never reads `PairRequest.deviceInfo`, which
/// this type never even sees, so a phone claiming a key other than the one it actually presented
/// on the handshake can never produce an accepted proof (SPEC.md §2: "never from any field of the
/// `PairRequest` body").
///
/// A `PairRequest` on a connection ``PeerAuthorizer`` (E12-02) didn't classify
/// `.pairingCandidate` for this attempt -- e.g. an already-`.trusted` connection replaying a stray
/// `PairRequest` -- is rejected before anything is computed: SPEC.md's proof recomputation is only
/// ever meaningful for the one candidate slot the pairing window itself is tracking.
public struct PairProofVerifier: PairRequestVerifier {
    private let macSpkiDerProvider: @Sendable () -> Data
    private let handshakeSpkiDerProvider: @Sendable () -> Data?
    private let connectionDecisionProvider: @Sendable () -> PeerAuthorizationDecision
    private let comparator: any ByteComparator

    /// - Parameters:
    ///   - macSpkiDerProvider: The Mac's own certificate SPKI DER (its SHA-256 is the QR `fp` the
    ///     phone scanned). Read lazily on every call, rather than captured once, so identity
    ///     rotation (E70) is reflected automatically.
    ///   - handshakeSpkiDerProvider: The candidate connection's phone SPKI DER, exactly as
    ///     ``PeerVerifier`` (E12-02) observed it on this TLS handshake -- `nil` if no candidate
    ///     connection currently occupies the slot this verify call is for.
    ///   - connectionDecisionProvider: This candidate connection's ``PeerAuthorizationDecision``
    ///     (E12-02) at the moment of this `PairRequest`; only `.pairingCandidate` may ever
    ///     produce a valid proof.
    ///   - comparator: Defaults to ``ConstantTimeByteComparator``; tests substitute a spy.
    public init(
        macSpkiDerProvider: @escaping @Sendable () -> Data,
        handshakeSpkiDerProvider: @escaping @Sendable () -> Data?,
        connectionDecisionProvider: @escaping @Sendable () -> PeerAuthorizationDecision,
        comparator: any ByteComparator = ConstantTimeByteComparator()
    ) {
        self.macSpkiDerProvider = macSpkiDerProvider
        self.handshakeSpkiDerProvider = handshakeSpkiDerProvider
        self.connectionDecisionProvider = connectionDecisionProvider
        self.comparator = comparator
    }

    public func verify(proof: Data, secret: Data, challenge: Data) -> Bool {
        guard connectionDecisionProvider() == .pairingCandidate else { return false }
        guard let phoneSpkiDer = handshakeSpkiDerProvider() else { return false }
        guard let expected = try? PairingProof.compute(
            secret: secret,
            macSpkiDer: macSpkiDerProvider(),
            phoneSpkiDer: phoneSpkiDer,
            channelBinding: challenge
        ) else {
            return false
        }
        return comparator.compare(expected, proof)
    }
}
