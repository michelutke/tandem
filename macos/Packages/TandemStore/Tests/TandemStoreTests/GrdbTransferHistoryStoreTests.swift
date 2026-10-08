import Foundation
import GRDB
import Testing
@testable import TandemStore

struct GrdbTransferHistoryStoreTests {
    private static func record(
        _ id: String,
        at finishedAtMs: Int64,
        outcome: TransferOutcome = .completed,
        bookmark: Data? = nil
    ) -> TransferRecord {
        TransferRecord(
            id: id, direction: .phoneToMac, name: "\(id).pdf", sizeBytes: 42,
            finishedAtMs: finishedAtMs, outcome: outcome, savedFileBookmark: bookmark
        )
    }

    private static func makeStore() throws -> (GrdbTransferHistoryStore, URL) {
        let url = try SmsFixtures.makeTempDirectory().appendingPathComponent("transfers.sqlite")
        return (try GrdbTransferHistoryStore.open(at: url), url)
    }

    @Test
    func append_threeRecords_listsNewestFirst() async throws {
        let (store, _) = try Self.makeStore()
        try await store.append(Self.record("a", at: 1))
        try await store.append(Self.record("c", at: 3))
        try await store.append(Self.record("b", at: 2))

        #expect(try await store.list().map(\.id) == ["c", "b", "a"])
    }

    @Test
    func append_allFields_roundTrip() async throws {
        let (store, _) = try Self.makeStore()
        let saved = TransferRecord(
            id: "x", direction: .macToPhone, name: "x.png", sizeBytes: 7, finishedAtMs: 9,
            outcome: .failed(reason: "ioError"), savedFileBookmark: Data([1, 2, 3])
        )
        try await store.append(saved)

        #expect(try await store.list() == [saved])
    }

    @Test
    func append_cancelledOutcome_roundTrips() async throws {
        let (store, _) = try Self.makeStore()
        try await store.append(Self.record("a", at: 1, outcome: .cancelled))

        #expect(try await store.list().first?.outcome == .cancelled)
    }

    @Test
    func append_sameIdTwice_keepsOneRow() async throws {
        let (store, _) = try Self.makeStore()
        try await store.append(Self.record("a", at: 1))
        try await store.append(Self.record("a", at: 2, outcome: .cancelled))

        let listed = try await store.list()
        #expect(listed.count == 1)
        #expect(listed.first?.outcome == .cancelled)
    }

    @Test
    func append_beyondCap_prunesOldest() async throws {
        let (store, _) = try Self.makeStore()
        let cap = GrdbTransferHistoryStore.maxRecords
        for index in 0..<(cap + 5) {
            try await store.append(Self.record("t\(index)", at: Int64(index)))
        }

        let listed = try await store.list()
        #expect(listed.count == cap)
        #expect(listed.first?.id == "t\(cap + 4)")
        #expect(listed.last?.id == "t5")
    }

    @Test
    func clear_removesEverything() async throws {
        let (store, _) = try Self.makeStore()
        try await store.append(Self.record("a", at: 1))
        try await store.clear()

        #expect(try await store.list().isEmpty)
    }

    @Test
    func reopen_keepsRecords() async throws {
        let (first, url) = try Self.makeStore()
        try await first.append(Self.record("a", at: 1))
        try first.close()

        let reopened = try GrdbTransferHistoryStore.open(at: url)
        #expect(try await reopened.list().map(\.id) == ["a"])
    }

    @Test
    func migrator_freshDatabase_createsTransferTable() throws {
        let queue = try DatabaseQueue()
        try GrdbTransferHistoryStore.migrator.migrate(queue)

        let columns = try queue.read { try $0.columns(in: "transfer").map(\.name) }
        #expect(columns == [
            "id", "direction", "display_name", "size_bytes", "finished_at_ms", "outcome", "reason", "saved_bookmark"
        ])
    }

    @Test
    func transferDatabaseFile_created_hasPosixMode0600() async throws {
        let (store, url) = try Self.makeStore()
        try await store.append(Self.record("a", at: 1))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
