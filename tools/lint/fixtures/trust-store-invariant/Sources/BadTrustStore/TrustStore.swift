import Foundation

/// Fixture module for E13-11 trust-store invariant test: demonstrates a hostname-keyed
/// lookup method that violates invariant 3 (fingerprint-only keying). The trust-store
/// check must fail on this module.
public struct BadTrustStore {
    /// VIOLATION: lookup by hostname instead of fingerprint.
    public func get(host: String) -> String? {
        nil
    }

    /// VIOLATION: delete by IP address instead of fingerprint.
    public func delete(ipAddress: String) throws {
    }
}
