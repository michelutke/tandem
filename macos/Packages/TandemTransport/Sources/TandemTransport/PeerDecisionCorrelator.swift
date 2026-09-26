import Foundation
import Security
import TandemCrypto

/// Correlates a ``PeerVerifier`` decision (E12-02) with the specific `NWConnection` it belongs to,
/// keyed by the identity of the `sec_protocol_metadata_t` both the verify callback and that same
/// connection's own later `.metadata(definition:)` read observe: that TLS metadata object is
/// intrinsic to one connection's own handshake, never shared or reused across connections, even
/// though a listener's single `sec_protocol_verify_t` closure instance handles every connection's
/// verify callback. Session wiring (E12-12) uses this to recover the peer's decision and SPKI
/// fingerprint once a connection reaches `.ready`, instead of re-deriving them from the
/// (by-then-gone) `sec_trust_t`.
///
/// A plain lock-based class, not an actor: ``record(metadataIdentifier:decision:fingerprint:)``
/// MUST complete synchronously, before the verify block's own `complete(_:)` call returns control
/// to `Network.framework` and the connection is free to race ahead to `.ready` -- an `actor` would
/// make every call here `async`, forcing callers back to a `Task { await ... }` at the verify
/// callback site (itself synchronous), reintroducing the exact ordering race this type exists to
/// close (a fire-and-forget record losing to `.ready`'s own `take`, or an `ObjectIdentifier` reused
/// by a later connection before an earlier one's record task runs).
public final class PeerDecisionCorrelator: @unchecked Sendable {
    public struct Decision: Sendable {
        public let decision: PeerAuthorizationDecision
        public let fingerprint: SpkiFingerprint?
    }

    private let lock = NSLock()
    private var decisions: [ObjectIdentifier: Decision] = [:]

    public init() {}

    /// Called from ``PeerVerifier/makeVerifyBlock(trustStore:window:onDecision:)``'s `onDecision`
    /// hook, before it calls `complete(_:)`, keyed by `ObjectIdentifier(metadata)` (computed by the
    /// caller: `sec_protocol_metadata_t` itself is not `Sendable`, so it never crosses a boundary
    /// here).
    public func record(
        metadataIdentifier: ObjectIdentifier,
        decision: PeerAuthorizationDecision,
        fingerprint: SpkiFingerprint?
    ) {
        lock.lock()
        decisions[metadataIdentifier] = Decision(decision: decision, fingerprint: fingerprint)
        lock.unlock()
    }

    /// Called once a connection reaches `.ready`. Removes the entry so this instance's storage
    /// never grows unbounded across the listener's lifetime; `nil` if no decision was ever recorded
    /// for this exact metadata object.
    public func take(metadataIdentifier: ObjectIdentifier) -> Decision? {
        lock.lock()
        defer { lock.unlock() }
        return decisions.removeValue(forKey: metadataIdentifier)
    }

    /// Called for a connection that reaches `.failed`/`.cancelled` without ever reaching `.ready`
    /// (e.g. it passed `PeerVerifier` but reset before the ALPN check, or `PeerVerifier` rejected
    /// it outright): drops any entry recorded for it, so a later connection cannot inherit a stale
    /// `.trusted` decision through a reused `ObjectIdentifier`.
    public func drop(metadataIdentifier: ObjectIdentifier) {
        lock.lock()
        decisions.removeValue(forKey: metadataIdentifier)
        lock.unlock()
    }
}
