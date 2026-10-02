import Foundation
import Testing
import TandemCrypto
@testable import TandemStore

struct GrdbSmsStoreTests {
    private let peerA = SmsFixtures.peerA

    private func databaseURL() throws -> URL {
        try SmsFixtures.makeTempDirectory().appendingPathComponent("Tandem/sms.sqlite")
    }

    private func seed(_ store: GrdbSmsStore) async throws {
        try await store.applyPage(
            peer: peerA,
            threads: [SmsFixtures.thread(1)],
            messages: [SmsFixtures.message(1), SmsFixtures.message(2)],
            cursors: SmsFixtures.cursors
        )
    }

    @Test
    func reopen_afterClose_returnsEveryWrittenRow() async throws {
        let url = try databaseURL()
        let store = try GrdbSmsStore.open(at: url)
        try await seed(store)
        try store.close()

        let reopened = try GrdbSmsStore.open(at: url)

        #expect(try await reopened.messages(peer: peerA, threadId: 1).map(\.id) == [1, 2])
        #expect(try await reopened.threads(peer: peerA).count == 1)
        #expect(try await reopened.cursors(peer: peerA) == SmsFixtures.cursors)
    }

    @Test
    func open_databaseAndSidecars_haveMode0600() async throws {
        let url = try databaseURL()
        let store = try GrdbSmsStore.open(at: url)
        try await seed(store)

        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
            #expect(permissions == 0o600, "\(url.lastPathComponent + suffix)")
        }
    }

    @Test
    func open_databaseAndSidecars_areExcludedFromBackup() async throws {
        let url = try databaseURL()
        let store = try GrdbSmsStore.open(at: url)
        try await seed(store)

        for suffix in ["", "-wal", "-shm"] {
            let values = try URL(fileURLWithPath: url.path + suffix).resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true, "\(url.lastPathComponent + suffix)")
        }
    }

    @Test
    func open_whereSupported_fileProtectionIsCompleteUntilFirstUserAuthentication() throws {
        let url = try databaseURL()
        _ = try GrdbSmsStore.open(at: url)

        let values = try url.resourceValues(forKeys: [.fileProtectionKey])
        if let protection = values.fileProtection {
            #expect(protection == .completeUntilFirstUserAuthentication)
        }
    }

    @Test
    func defaultDatabaseURL_resolvesToApplicationSupportTandemSmsSqlite() throws {
        let url = try TandemDatabaseFactory.defaultDatabaseURL(fileName: "sms.sqlite")

        #expect(url.pathComponents.suffix(3) == ["Application Support", "Tandem", "sms.sqlite"])
    }
}
