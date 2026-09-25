import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemStore

@Suite("TrustStore")
struct TrustStoreTests {

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private static func makeRecord(
        fingerprint: SpkiFingerprint,
        displayName: String = "MacBook",
        pairedAt: Date = Date(timeIntervalSince1970: 0),
        lastSeen: Date = Date(timeIntervalSince1970: 0),
        capabilities: [String] = ["clipboard", "files"]
    ) -> PeerRecord {
        PeerRecord(
            fingerprint: fingerprint,
            displayName: displayName,
            pairedAt: pairedAt,
            lastSeen: lastSeen,
            capabilities: capabilities
        )
    }

    @Test
    func trustStore_putThenGetByFingerprint_returnsEqualRecord() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = Self.makeRecord(fingerprint: try Self.fingerprint(0x01))

        try store.put(record)

        #expect(try store.get(record.fingerprint) == record)
    }

    @Test
    func trustStore_getUnknownFingerprint_returnsNil() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())

        #expect(try store.get(try Self.fingerprint(0x02)) == nil)
    }

    @Test
    func trustStore_listAfterTwoPuts_returnsBothRecords() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let first = Self.makeRecord(fingerprint: try Self.fingerprint(0x03), displayName: "MacBook")
        let second = Self.makeRecord(fingerprint: try Self.fingerprint(0x04), displayName: "iPhone")

        try store.put(first)
        try store.put(second)

        let records = try store.list()
        #expect(records.count == 2)
        #expect(records.contains(first))
        #expect(records.contains(second))
    }

    @Test
    func trustStore_putExistingFingerprint_replacesRecord() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let fingerprint = try Self.fingerprint(0x05)
        try store.put(Self.makeRecord(fingerprint: fingerprint, displayName: "MacBook"))

        let updated = Self.makeRecord(
            fingerprint: fingerprint,
            displayName: "MacBook Pro",
            lastSeen: Date(timeIntervalSince1970: 60)
        )
        try store.put(updated)

        #expect(try store.get(fingerprint) == updated)
        #expect(try store.list().count == 1)
    }

    @Test
    func trustStore_put_recordsAfterFirstUnlockThisDeviceOnly() throws {
        let keychain = InMemoryKeychainStore()
        let store = TrustStore(keychainStore: keychain)
        let record = Self.makeRecord(fingerprint: try Self.fingerprint(0x06))

        try store.put(record)

        #expect(
            keychain.recordedAccessibility(
                service: TrustStore.peerRecordService,
                account: record.fingerprint.hexString
            ) == .afterFirstUnlockThisDeviceOnly
        )
    }

    @Test
    func trustStore_keychainLocked_getThrowsLockedNotNil() throws {
        let keychain = InMemoryKeychainStore()
        let store = TrustStore(keychainStore: keychain)
        keychain.failNextOperation(with: .locked)

        #expect(throws: KeychainError.locked) {
            try store.get(try Self.fingerprint(0x07))
        }
    }

    @Test
    func trustStore_put_usesDataProtectionKeychainOwnGroup() throws {
        let keychain = InMemoryKeychainStore()
        let store = TrustStore(keychainStore: keychain)
        let record = Self.makeRecord(fingerprint: try Self.fingerprint(0x08))

        try store.put(record)

        // TrustStore only ever reaches the Keychain through `KeychainStore.addGenericPassword`
        // under the single fixed `peerRecordService` -- never a per-record or peer-controlled
        // namespace -- which is what lets `SecItemKeychainStore` guarantee every trust item lands
        // in the data-protection keychain, in the app's own access group, with no override point
        // (the protocol has no access-group parameter at all).
        let items = try keychain.listGenericPasswords(service: TrustStore.peerRecordService)
        #expect(items.count == 1)
        #expect(items.first?.account == record.fingerprint.hexString)
    }

    @Test
    func trustStore_deleteThenGet_returnsNil() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = Self.makeRecord(fingerprint: try Self.fingerprint(0x09))
        try store.put(record)

        try store.delete(record.fingerprint)

        #expect(try store.get(record.fingerprint) == nil)
    }

    @Test
    func unpair_thenGetSameProcess_returnsNil() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = Self.makeRecord(fingerprint: try Self.fingerprint(0x0A))
        try store.put(record)

        try store.unpair(record.fingerprint)

        #expect(try store.get(record.fingerprint) == nil)
    }

    @Test
    func unpair_thenNewStoreInstance_recordStillAbsent() throws {
        let keychain = InMemoryKeychainStore()
        let store = TrustStore(keychainStore: keychain)
        let record = Self.makeRecord(fingerprint: try Self.fingerprint(0x0B))
        try store.put(record)

        try store.unpair(record.fingerprint)

        let newStore = TrustStore(keychainStore: keychain)
        #expect(try newStore.get(record.fingerprint) == nil)
    }

    @Test
    func unpair_otherPeerRecords_remainUnchanged() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let first = Self.makeRecord(fingerprint: try Self.fingerprint(0x0C), displayName: "MacBook")
        let second = Self.makeRecord(fingerprint: try Self.fingerprint(0x0D), displayName: "iPhone")

        try store.put(first)
        try store.put(second)

        try store.unpair(first.fingerprint)

        #expect(try store.get(first.fingerprint) == nil)
        #expect(try store.get(second.fingerprint) == second)
    }
}

/// Manual gate: only runs with `TANDEM_KEYCHAIN_INTEGRATION_TESTS=1` set (see
/// `SecItemKeychainStoreTests` in TandemCryptoTests).
private let keychainIntegrationTestsEnabled =
    ProcessInfo.processInfo.environment["TANDEM_KEYCHAIN_INTEGRATION_TESTS"] == "1"

/// Real Keychain access needs a signed host with the `keychain-access-groups` entitlement and must
/// never run unattended or touch a developer's real login keychain. Gated behind an explicit
/// opt-in env var; `swift test` never runs this by default.
@Suite("TrustStore hosted", .enabled(if: keychainIntegrationTestsEnabled))
struct TrustStoreHostedTests {

    @Test
    func trustStore_hostedKeychain_recordSurvivesNewStoreInstance() throws {
        let fingerprintBytes = Data(repeating: 0x0A, count: SpkiFingerprint.byteCount)
        let fingerprint = try SpkiFingerprint(bytes: fingerprintBytes)
        let record = PeerRecord(
            fingerprint: fingerprint,
            displayName: "Hosted MacBook",
            pairedAt: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0),
            capabilities: ["clipboard"]
        )
        defer {
            try? SecItemKeychainStore().deleteGenericPassword(
                service: TrustStore.peerRecordService,
                account: fingerprint.hexString
            )
        }

        try TrustStore(keychainStore: SecItemKeychainStore()).put(record)

        #expect(try TrustStore(keychainStore: SecItemKeychainStore()).get(fingerprint) == record)
    }
}
