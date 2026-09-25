import Foundation
import TandemCrypto

/// One paired peer (E13-06), keyed by ``SpkiFingerprint`` (TandemCrypto, E10-08). Same shape as
/// the Android trust store's record (E13-02): a display name, pairing/last-seen timestamps and
/// the peer's advertised capabilities.
public struct PeerRecord: Equatable, Sendable, Codable {
    public let fingerprint: SpkiFingerprint
    public var displayName: String
    public var pairedAt: Date
    public var lastSeen: Date
    public var capabilities: [String]

    public init(
        fingerprint: SpkiFingerprint,
        displayName: String,
        pairedAt: Date,
        lastSeen: Date,
        capabilities: [String]
    ) {
        self.fingerprint = fingerprint
        self.displayName = displayName
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
        self.capabilities = capabilities
    }
}
