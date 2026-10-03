import Foundation
import Testing
@testable import TandemStore

struct GrdbContactsStoreTests {
    @Test
    func contactsDatabaseFile_created_hasPosixMode0600() async throws {
        let url = try SmsFixtures.makeTempDirectory().appendingPathComponent("contacts.sqlite")
        let store = try GrdbContactsStore.open(at: url)
        try await store.apply(
            peer: SmsFixtures.peerA,
            contacts: [ContactRecord(contactId: "1", displayName: "x", phoneNumbers: [], updatedAtMs: 1)],
            deletedContactIds: [],
            watermarkMs: 1
        )

        for suffix in ["", "-wal", "-shm"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path + suffix)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
            #expect(permissions == 0o600, "\(url.lastPathComponent + suffix)")
        }
    }

    @Test
    func contactsDatabaseFile_created_isExcludedFromBackup() throws {
        let url = try SmsFixtures.makeTempDirectory().appendingPathComponent("contacts.sqlite")
        _ = try GrdbContactsStore.open(at: url)

        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test
    func contactsStore_reopened_keepsContactsAndWatermark() async throws {
        let url = try SmsFixtures.makeTempDirectory().appendingPathComponent("contacts.sqlite")
        let first = try GrdbContactsStore.open(at: url)
        try await first.apply(
            peer: SmsFixtures.peerA,
            contacts: [ContactRecord(contactId: "1", displayName: "x", phoneNumbers: [], updatedAtMs: 1)],
            deletedContactIds: [],
            watermarkMs: 9
        )
        try first.close()

        let second = try GrdbContactsStore.open(at: url)
        #expect(try await second.contactIds(peer: SmsFixtures.peerA) == ["1"])
        #expect(try await second.watermarkMs(peer: SmsFixtures.peerA) == 9)
    }
}
