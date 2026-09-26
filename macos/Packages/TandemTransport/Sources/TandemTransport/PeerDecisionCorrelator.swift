import Foundation
import Security
import TandemCrypto

/// Correlates a ``PeerVerifier`` decision (E12-02) with the specific `NWConnection` it belongs to,
/// keyed by the identity of the `sec_protocol_metadata_t` both the verify callback and that same
/// connection's own later `.metadata(definition:)` read observe: that TLS metadata object is
/// intrinsic to one connection's own handshake, never shared or reused across connections, even
/// though a listener's single `sec_protocol_verify_t` closure instance handles every connection's
/// verify callback. Session wiring (E12-12) uses this to recover the peer SPKI fingerprint
/// ``PeerVerifier`` already computed once a connection reaches `.ready`, instead of re-deriving it
/// from the (by-then-gone) `sec_trust_t`.
public actor PeerDecisionCorrelator {
    private var fingerprints: [ObjectIdentifier: SpkiFingerprint] = [:]

    public init() {}

    /// Called from ``PeerVerifier/makeVerifyBlock(trustStore:window:onDecision:)``'s `onDecision`
    /// hook, keyed by `ObjectIdentifier(metadata)` (computed by the caller: `sec_protocol_metadata_t`
    /// itself is not `Sendable`, so it never crosses this actor's isolation boundary). Does nothing
    /// for a rejected peer (`fingerprint == nil`) or one whose SPKI never parsed.
    public func record(metadataIdentifier: ObjectIdentifier, fingerprint: SpkiFingerprint?) {
        guard let fingerprint else { return }
        fingerprints[metadataIdentifier] = fingerprint
    }

    /// Called once a connection reaches `.ready`. Removes the entry so this actor's storage never
    /// grows unbounded across the listener's lifetime; `nil` if no decision was ever recorded for
    /// this exact metadata object (a rejected peer never reaches `.ready` to ask, so this should
    /// only be `nil` if the verify callback and `.ready` somehow observed different metadata
    /// objects for the same connection).
    public func take(metadataIdentifier: ObjectIdentifier) -> SpkiFingerprint? {
        fingerprints.removeValue(forKey: metadataIdentifier)
    }
}
