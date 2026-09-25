import Foundation
import TandemCrypto

/// Peer record CRUD keyed by ``SpkiFingerprint`` (E13-06). Persists to the Keychain as
/// generic-password items, but only through ``KeychainStore`` (E10-16) -- never
/// `SecItem*`/`SecKey*` directly -- so unit tests run against `InMemoryKeychainStore`
/// (TandemTestSupport) and the boundary check (E10-14) stays green; one hosted `integration:` test
/// exercises `SecItemKeychainStore`. `KeychainStore`'s generic-password items are always written to
/// the data-protection keychain in the app's own access group only (`SecItemKeychainStore`'s own
/// guarantee) -- `TrustStore` never has a way to override that, since the protocol exposes no
/// access-group parameter.
/// Schema version and migration support (E13-07).
public struct TrustStore: Sendable {
    /// Fixed Keychain service every peer record is stored under, analogous to
    /// `identityKeyApplicationTag` (E10-05).
    public static let peerRecordService = "com.tandem.trust.peer.v1"

    /// Fixed Keychain service for schema version metadata.
    private static let schemaVersionService = "com.tandem.trust.schema"
    private static let schemaVersionAccount = "version"

    /// Current schema version.
    private static let currentSchemaVersion: Int = 1

    private let keychainStore: any KeychainStore

    public init(keychainStore: any KeychainStore) {
        self.keychainStore = keychainStore
    }

    /// Adds the record for `record.fingerprint`, or replaces it if one already exists.
    public func put(_ record: PeerRecord) throws {
        let data = try Self.encoder.encode(record)
        let account = record.fingerprint.hexString
        do {
            try keychainStore.addGenericPassword(
                service: Self.peerRecordService,
                account: account,
                data: data,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        } catch KeychainError.duplicateItem {
            try keychainStore.updateGenericPassword(service: Self.peerRecordService, account: account, data: data)
        }
    }

    /// The record for `fingerprint`, or `nil` if none exists. A locked Keychain throws
    /// `KeychainError.locked` rather than returning `nil`, so a caller can't mistake "locked" for
    /// "unknown peer".
    public func get(_ fingerprint: SpkiFingerprint) throws -> PeerRecord? {
        do {
            let data = try keychainStore.copyGenericPassword(
                service: Self.peerRecordService,
                account: fingerprint.hexString
            )
            return try Self.decoder.decode(PeerRecord.self, from: data)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

    /// Every paired peer, for the paired-devices UI (E14-14).
    public func list() throws -> [PeerRecord] {
        try keychainStore.listGenericPasswords(service: Self.peerRecordService)
            .map { try Self.decoder.decode(PeerRecord.self, from: $0.data) }
    }

    /// Removes the record for `fingerprint`. Throws `KeychainError.itemNotFound` if none exists.
    public func delete(_ fingerprint: SpkiFingerprint) throws {
        try keychainStore.deleteGenericPassword(service: Self.peerRecordService, account: fingerprint.hexString)
    }

    /// Returns the current schema version. Defaults to 1 if no version is set.
    public func schemaVersion() throws -> Int {
        do {
            let data = try keychainStore.copyGenericPassword(
                service: Self.schemaVersionService,
                account: Self.schemaVersionAccount
            )
            let decoded = try Self.decoder.decode([String: Int].self, from: data)
            return decoded["version"] ?? 1
        } catch KeychainError.itemNotFound {
            // No version stored yet; assume v1 for backward compatibility
            return 1
        }
    }

    /// Runs the v1-to-v2 migration: reads all v1 records, updates schema version to 2.
    /// In this initial scaffold, all records are preserved as-is; future migrations can
    /// transform record fields as needed.
    public static func runMigrationV1ToV2(keychainStore: any KeychainStore) throws {
        // Read all current records (which are v1 format)
        let items = try keychainStore.listGenericPasswords(service: Self.peerRecordService)
        let records: [PeerRecord] = try items.map { try Self.decoder.decode(PeerRecord.self, from: $0.data) }

        // Re-write records as-is (in this scaffold, no transformation needed)
        for record in records {
            let data = try Self.encoder.encode(record)
            let account = record.fingerprint.hexString
            try keychainStore.updateGenericPassword(
                service: Self.peerRecordService,
                account: account,
                data: data
            )
        }

        // Update schema version to 2
        let versionData = try Self.encoder.encode(["version": 2])
        do {
            try keychainStore.addGenericPassword(
                service: Self.schemaVersionService,
                account: Self.schemaVersionAccount,
                data: versionData,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        } catch KeychainError.duplicateItem {
            try keychainStore.updateGenericPassword(
                service: Self.schemaVersionService,
                account: Self.schemaVersionAccount,
                data: versionData
            )
        }
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
