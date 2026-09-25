import Foundation
import TandemCrypto

/// The verify-callback pin decision (`docs/protocol/SPEC.md` §1 "Verify-callback algorithm").
/// Only the Mac, as the listening side, ever produces ``pairingCandidate`` -- the phone has no
/// equivalent relaxation (invariant 4).
public enum PeerAuthorizationDecision: Sendable, Equatable {
    /// The candidate fingerprint matched an entry in the trust store.
    case trusted
    /// No trust-store match, but a pairing window is open with no other candidate in flight
    /// (D-18): admitted for the pairing exchange on this one connection only.
    case pairingCandidate
    /// No trust-store match and no pairing-window relaxation applies; the handshake MUST fail
    /// (SPEC.md §1).
    case rejected
}

/// The trust store's read surface, as ``PeerAuthorizer`` needs it -- deliberately narrower than
/// `TrustStore`'s full CRUD API (E13-06, `TandemStore`) so this decision is unit-testable without
/// a real Keychain. A production conforming type adapts `TrustStore` to this protocol.
public protocol TrustStoreReader: Sendable {
    /// Whether `fingerprint` is a paired peer's pin. Rethrows any underlying storage error (e.g.
    /// a locked Keychain) rather than mapping it to `false` -- ``PeerAuthorizer`` must never treat
    /// "couldn't read the trust store" the same as "confirmed unknown" (E13-06 acceptance).
    func contains(_ fingerprint: SpkiFingerprint) throws -> Bool
}

/// The pairing window's read surface, as ``PeerAuthorizer`` needs it (`docs/protocol/SPEC.md` §2
/// "Pairing"). E14-02's pairing-window state machine conforms in production; tests use a
/// fixed-value fake.
public protocol PairingWindowState: Sendable {
    /// Whether a pairing window is currently open.
    var isOpen: Bool { get }
    /// Whether another unknown-certificate connection is already occupying the single
    /// pairing-candidate slot (`docs/planning/decisions.md` D-18).
    var candidateInFlight: Bool { get }
}

/// SPEC.md §1's verify-callback pin decision, factored out as a pure function (E12-02) so the
/// trust-store/pairing-window logic is unit-testable without a real TLS handshake. ``PeerVerifier``
/// is the glue that calls this from the real `sec_protocol_verify_t` block.
public enum PeerAuthorizer {
    /// Decides `spki` -- a peer leaf certificate's candidate SPKI DER, not yet validated -- against
    /// `trustStore` and `window`, in the order SPEC.md §1 documents:
    /// 1. Validate `spki` is an uncompressed P-256 SPKI of the expected byte count and compute its
    ///    fingerprint; any other type, curve, or encoding is `.rejected` before step 2 -- no
    ///    fingerprint is ever compared for a non-conforming key.
    /// 2. Compare the candidate fingerprint, in constant time (invariant 6, `SpkiFingerprint.matches`,
    ///    used internally by `trustStore.contains`), against every fingerprint the trust store
    ///    holds. A match is always `.trusted`, regardless of window state.
    /// 3. A trust-store read error is always `.rejected`, never `.trusted`.
    /// 4. Otherwise: an open window with no candidate already in flight is `.pairingCandidate`;
    ///    everything else (window closed, or the single candidate slot already occupied, D-18) is
    ///    `.rejected`.
    public static func decide(
        spki: Data,
        trustStore: any TrustStoreReader,
        window: any PairingWindowState
    ) -> PeerAuthorizationDecision {
        guard let fingerprint = try? SpkiFingerprint.of(spkiDer: spki) else {
            return .rejected
        }

        let isTrusted: Bool
        do {
            isTrusted = try trustStore.contains(fingerprint)
        } catch {
            return .rejected
        }

        if isTrusted {
            return .trusted
        }

        if window.isOpen, !window.candidateInFlight {
            return .pairingCandidate
        }

        return .rejected
    }
}
