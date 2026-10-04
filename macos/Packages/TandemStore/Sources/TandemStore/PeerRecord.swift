import Foundation
import TandemCrypto

/// The previous primary pin kept after a key rotation (E70-05, SPEC.md #key-rotation "Grace
/// pin"): accepted for at most one subsequent session and never after `expiresAt`.
public struct GracePin: Equatable, Sendable, Codable {
    public let fingerprint: SpkiFingerprint
    public let expiresAt: Date
    /// Set once a session authenticated by this pin reached Ready; no further session may use it.
    public var used: Bool

    public init(fingerprint: SpkiFingerprint, expiresAt: Date, used: Bool = false) {
        self.fingerprint = fingerprint
        self.expiresAt = expiresAt
        self.used = used
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fingerprint: try container.decode(SpkiFingerprint.self, forKey: .fingerprint),
            expiresAt: try container.decode(Date.self, forKey: .expiresAt),
            used: try container.decodeIfPresent(Bool.self, forKey: .used) ?? false
        )
    }
}

/// One paired peer (E13-06), keyed by ``SpkiFingerprint`` (TandemCrypto, E10-08). Same shape as
/// the Android trust store's record (E13-02): a display name, pairing/last-seen timestamps and
/// the peer's advertised capabilities.
///
/// Schema v2 (E13-07, E70-05): `fingerprint` is the peer's current primary pin and changes on a
/// key rotation, while `recordId` is the fingerprint the record was first stored under and is its
/// permanent Keychain account, so a rotation is one in-place item update. `gracePin` is `nil`
/// unless a rotation left the previous pin in its grace period. A v1 record decodes with
/// `recordId == fingerprint` and no grace pin.
public struct PeerRecord: Equatable, Sendable, Codable {
    public var fingerprint: SpkiFingerprint
    public var displayName: String
    public var pairedAt: Date
    public var lastSeen: Date
    public var capabilities: [String]
    public var gracePin: GracePin?
    public let recordId: SpkiFingerprint

    public init(
        fingerprint: SpkiFingerprint,
        displayName: String,
        pairedAt: Date,
        lastSeen: Date,
        capabilities: [String],
        gracePin: GracePin? = nil,
        recordId: SpkiFingerprint? = nil
    ) {
        self.fingerprint = fingerprint
        self.displayName = displayName
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
        self.capabilities = capabilities
        self.gracePin = gracePin
        self.recordId = recordId ?? fingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fingerprint = try container.decode(SpkiFingerprint.self, forKey: .fingerprint)
        self.init(
            fingerprint: fingerprint,
            displayName: try container.decode(String.self, forKey: .displayName),
            pairedAt: try container.decode(Date.self, forKey: .pairedAt),
            lastSeen: try container.decode(Date.self, forKey: .lastSeen),
            capabilities: try container.decode([String].self, forKey: .capabilities),
            gracePin: try container.decodeIfPresent(GracePin.self, forKey: .gracePin),
            recordId: try container.decodeIfPresent(SpkiFingerprint.self, forKey: .recordId)
        )
    }
}
