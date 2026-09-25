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
public struct TrustStore: Sendable {
    /// Fixed Keychain service every peer record is stored under, analogous to
    /// `identityKeyApplicationTag` (E10-05).
    public static let peerRecordService = "com.tandem.trust.peer.v1"

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

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
