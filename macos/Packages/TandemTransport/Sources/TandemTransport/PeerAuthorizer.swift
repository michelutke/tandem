import Foundation
import TandemCrypto

/// The verify-callback pin decision (`docs/protocol/SPEC.md` §1 "Verify-callback algorithm").
/// Only the Mac, as the listening side, ever produces ``pairingCandidate`` -- the phone has no
/// equivalent relaxation (invariant 4).
public enum PeerAuthorizationDecision: Sendable, Hashable {
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

/// Opaque generation token a successful ``PairingWindowState/admitCandidate()`` claim returns
/// (E14-16 finding #2, `docs/planning/decisions.md` D-18): every later mutation of *that one*
/// candidate's slot (hellos completed, a submitted proof, release, the owner's accept/decline)
/// must be scoped to this exact token, so a stale candidate -- one that already timed out or was
/// superseded by the window regenerating -- can never affect a different, currently-admitted
/// candidate's state just because the single slot happens to be occupied again. Equality is the
/// only operation callers need; the wrapped value is never inspected.
public struct PairingCandidateToken: Sendable, Equatable, Hashable {
    private let id: UUID

    public init() {
        self.id = UUID()
    }
}

/// The pairing window's read/claim surface, as ``PeerAuthorizer`` needs it (`docs/protocol/SPEC.md`
/// §2 "Pairing"). E14-02's pairing-window state machine conforms in production; tests use a
/// counting/fixed-value fake.
public protocol PairingWindowState: Sendable {
    /// Whether a pairing window is currently open.
    var isOpen: Bool { get }

    /// Atomically attempts to occupy the single pairing-candidate slot (`docs/planning/decisions.md`
    /// D-18, `docs/protocol/SPEC.md` §2 "Concurrency"): succeeds -- returns a fresh
    /// ``PairingCandidateToken`` scoping every later call for this one candidate, and claims the
    /// slot for the caller -- only if no other candidate is already in flight; otherwise leaves the
    /// slot untouched and returns `nil`. This single call MUST be the entire test-and-set: a
    /// separate "is a candidate in flight" read followed by a later claim would reopen the race this
    /// method exists to close (two concurrent verify callbacks could both read "no candidate" before
    /// either claims the slot).
    func admitCandidate() -> PairingCandidateToken?

    /// Frees the slot a prior ``admitCandidate()`` call claimed, if `token` still matches the
    /// current candidate -- a no-op otherwise (the slot was already freed, or has since been
    /// claimed by a different candidate this token no longer names). SPEC.md §2 "Concurrency": "The
    /// candidate slot ... is occupied from the moment the verify callback accepts the unknown
    /// certificate until that connection closes" -- so the real pairing-window state machine
    /// (E14-02) calls this from the candidate connection's own close/lifecycle handling, once it
    /// closes for any reason. Never called by ``PeerAuthorizer``/``PeerVerifier`` themselves, which
    /// only ever claim the slot, never release it -- release is a connection-lifecycle concern
    /// outside this pure decision function's scope.
    func releaseCandidate(_ token: PairingCandidateToken)
}

/// SPEC.md §1's verify-callback pin decision, factored out as a pure function (E12-02) so the
/// trust-store/pairing-window logic is unit-testable without a real TLS handshake. ``PeerVerifier``
/// is the glue that calls this from the real `sec_protocol_verify_t` block.
public enum PeerAuthorizer {
    /// ``decide(spki:trustStore:window:)``'s result: the decision itself, plus -- only for
    /// ``PeerAuthorizationDecision/pairingCandidate`` -- the ``PairingCandidateToken`` this exact
    /// call's ``PairingWindowState/admitCandidate()`` claim returned, so every later step of this
    /// one candidate's pairing dance (E14-16 finding #2) can be scoped to it. `nil` for `.trusted`
    /// and `.rejected`, which never claim the slot.
    public struct Outcome: Sendable, Equatable {
        public let decision: PeerAuthorizationDecision
        public let candidateToken: PairingCandidateToken?
    }

    /// Decides `spki` -- a peer leaf certificate's candidate SPKI DER, not yet validated -- against
    /// `trustStore` and `window`, in the order SPEC.md §1 documents:
    /// 1. Validate `spki` is an uncompressed P-256 SPKI of the expected byte count and compute its
    ///    fingerprint; any other type, curve, or encoding is `.rejected` before step 2 -- no
    ///    fingerprint is ever compared for a non-conforming key.
    /// 2. Compare the candidate fingerprint, in constant time (invariant 6, `SpkiFingerprint.matches`,
    ///    used internally by `trustStore.contains`), against every fingerprint the trust store
    ///    holds. A match is always `.trusted`, regardless of window state.
    /// 3. A trust-store read error is always `.rejected`, never `.trusted`.
    /// 4. Otherwise: an open window claims the single candidate slot (D-18,
    ///    ``PairingWindowState/admitCandidate()``) -- a successful claim is `.pairingCandidate`;
    ///    everything else (window closed, or the claim fails because the slot is already occupied)
    ///    is `.rejected`. The slot is claimed only here, after the store miss, and only while the
    ///    window is open -- never speculatively before either is known.
    public static func decide(
        spki: Data,
        trustStore: any TrustStoreReader,
        window: any PairingWindowState
    ) -> Outcome {
        guard let fingerprint = try? SpkiFingerprint.of(spkiDer: spki) else {
            return Outcome(decision: .rejected, candidateToken: nil)
        }

        let isTrusted: Bool
        do {
            isTrusted = try trustStore.contains(fingerprint)
        } catch {
            return Outcome(decision: .rejected, candidateToken: nil)
        }

        if isTrusted {
            return Outcome(decision: .trusted, candidateToken: nil)
        }

        guard window.isOpen else {
            return Outcome(decision: .rejected, candidateToken: nil)
        }

        guard let token = window.admitCandidate() else {
            return Outcome(decision: .rejected, candidateToken: nil)
        }
        return Outcome(decision: .pairingCandidate, candidateToken: token)
    }
}
