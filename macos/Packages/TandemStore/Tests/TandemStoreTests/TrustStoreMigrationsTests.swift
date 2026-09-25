import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemStore

@Suite("TrustStore Migrations")
struct TrustStoreMigrationsTests {

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
    func migration_v1FixtureOpened_allRecordsReadableVersionStill1() throws {
        let keychain = InMemoryKeychainStore()

        // Seed v1 fixture records directly as v1 JSON (no version wrapper)
        let fp1 = try Self.fingerprint(0x10)
        let fp2 = try Self.fingerprint(0x20)
        let record1 = Self.makeRecord(fingerprint: fp1, displayName: "First")
        let record2 = Self.makeRecord(fingerprint: fp2, displayName: "Second")

        let v1Data1 = try JSONEncoder().encode(record1)
        let v1Data2 = try JSONEncoder().encode(record2)

        try keychain.addGenericPassword(
            service: TrustStore.peerRecordService,
            account: fp1.hexString,
            data: v1Data1,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
        try keychain.addGenericPassword(
            service: TrustStore.peerRecordService,
            account: fp2.hexString,
            data: v1Data2,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )

        // Open store on v1 fixture
        let store = TrustStore(keychainStore: keychain)

        // All records should be readable
        #expect(try store.get(fp1) == record1)
        #expect(try store.get(fp2) == record2)
        let list = try store.list()
        #expect(list.count == 2)
        #expect(list.contains(record1))
        #expect(list.contains(record2))

        // Schema version should still be 1
        #expect(try store.schemaVersion() == 1)
    }

    @Test
    func migration_v1FixtureToSimulatedV2_allRecordsPreservedNewFieldDefaulted() throws {
        let keychain = InMemoryKeychainStore()

        // Seed v1 fixture records
        let fp1 = try Self.fingerprint(0x30)
        let fp2 = try Self.fingerprint(0x40)
        let record1 = Self.makeRecord(fingerprint: fp1, displayName: "Device1")
        let record2 = Self.makeRecord(fingerprint: fp2, displayName: "Device2")

        let v1Data1 = try JSONEncoder().encode(record1)
        let v1Data2 = try JSONEncoder().encode(record2)

        try keychain.addGenericPassword(
            service: TrustStore.peerRecordService,
            account: fp1.hexString,
            data: v1Data1,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
        try keychain.addGenericPassword(
            service: TrustStore.peerRecordService,
            account: fp2.hexString,
            data: v1Data2,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )

        // Simulate running v1->v2 migration
        try TrustStore.runMigrationV1ToV2(keychainStore: keychain)

        // After migration, all records should still be readable
        let store = TrustStore(keychainStore: keychain)
        let retrieved1 = try store.get(fp1)
        let retrieved2 = try store.get(fp2)

        #expect(retrieved1?.fingerprint == record1.fingerprint)
        #expect(retrieved1?.displayName == record1.displayName)
        #expect(retrieved1?.pairedAt == record1.pairedAt)
        #expect(retrieved1?.lastSeen == record1.lastSeen)
        #expect(retrieved1?.capabilities == record1.capabilities)

        #expect(retrieved2?.fingerprint == record2.fingerprint)
        #expect(retrieved2?.displayName == record2.displayName)
        #expect(retrieved2?.pairedAt == record2.pairedAt)
        #expect(retrieved2?.lastSeen == record2.lastSeen)
        #expect(retrieved2?.capabilities == record2.capabilities)

        // List should still return both
        let list = try store.list()
        #expect(list.count == 2)

        // Schema version should now be 2
        #expect(try store.schemaVersion() == 2)
    }
}
