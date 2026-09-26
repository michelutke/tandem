import Foundation
import TandemCrypto

/// Wall-clock time seam for injecting now (E00-24).
public typealias DateProvider = @Sendable () -> Date

/// Updates peer records in the trust store on Ready state (E12-14). Given the handshake SPKI
/// fingerprint and the peer's hello capabilities, updates only the matching record's lastSeen
/// to the current injected date and capabilities to the peer's advertised set.
/// Matches by fingerprint only (invariant 3); never creates a record or matches by any other field.
public struct PeerRecordUpdater: Sendable {
    private let trustStore: TrustStore
    private let dateProvider: DateProvider

    public init(trustStore: TrustStore, dateProvider: @escaping DateProvider) {
        self.trustStore = trustStore
        self.dateProvider = dateProvider
    }

    /// Updates the peer record matching `handshakeSpki` (if it exists) with the current time
    /// and the peer's advertised capabilities. Throws if the keychain is locked or other I/O fails.
    /// Invariant 3: match by fingerprint only; never create or match by any other field.
    public func updateOnReady(handshakeSpki: SpkiFingerprint, capabilities: [String]) throws {
        guard var record = try trustStore.get(handshakeSpki) else {
            // Record does not exist; do nothing (never create)
            return
        }
        record.lastSeen = dateProvider()
        record.capabilities = capabilities
        try trustStore.put(record)
    }
}
