import Foundation
import GRDB

/// GRDB/SQLite ``TransferHistoryStore`` at `Application Support/Tandem/transfers.sqlite`, opened
/// through ``TandemDatabaseFactory`` like ``GrdbContactsStore``. Never logs row content
/// (invariant 7).
public final class GrdbTransferHistoryStore: TransferHistoryStore {
    public static let databaseFileName = "transfers.sqlite"

    private let pool: DatabasePool

    private init(pool: DatabasePool) {
        self.pool = pool
    }

    public static func open(at url: URL) throws -> GrdbTransferHistoryStore {
        GrdbTransferHistoryStore(pool: try TandemDatabaseFactory.openPool(at: url, migrator: migrator))
    }

    public static func openDefault() throws -> GrdbTransferHistoryStore {
        try open(at: TandemDatabaseFactory.defaultDatabaseURL(fileName: databaseFileName))
    }

    public func close() throws {
        try pool.close()
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try database.execute(sql: """
                CREATE TABLE transfer (
                    id TEXT NOT NULL PRIMARY KEY,
                    direction TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    size_bytes INTEGER NOT NULL,
                    finished_at_ms INTEGER NOT NULL,
                    outcome TEXT NOT NULL,
                    reason TEXT,
                    saved_bookmark BLOB
                );
                CREATE INDEX transfer_finished ON transfer (finished_at_ms);
                """)
        }
        return migrator
    }

    public func append(_ record: TransferRecord) async throws {
        try await pool.write { database in
            try database.execute(
                sql: """
                    INSERT OR REPLACE INTO transfer
                    (id, direction, display_name, size_bytes, finished_at_ms, outcome, reason, saved_bookmark)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    record.id, record.direction.rawValue, record.name, record.sizeBytes,
                    record.finishedAtMs, record.outcome.storageName, record.outcome.storageReason,
                    record.savedFileBookmark
                ]
            )
            try database.execute(
                sql: """
                    DELETE FROM transfer WHERE rowid NOT IN (
                        SELECT rowid FROM transfer ORDER BY finished_at_ms DESC, rowid DESC LIMIT ?
                    )
                    """,
                arguments: [Self.maxRecords]
            )
        }
    }

    public func list() async throws -> [TransferRecord] {
        try await pool.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT * FROM transfer ORDER BY finished_at_ms DESC, rowid DESC"
            ).compactMap(Self.record(from:))
        }
    }

    public func clear() async throws {
        try await pool.write { database in
            try database.execute(sql: "DELETE FROM transfer")
        }
    }

    private static func record(from row: Row) -> TransferRecord? {
        guard let direction = TransferDirection(rawValue: row["direction"]),
              let outcome = TransferOutcome(storageName: row["outcome"], reason: row["reason"]) else { return nil }
        return TransferRecord(
            id: row["id"],
            direction: direction,
            name: row["display_name"],
            sizeBytes: row["size_bytes"],
            finishedAtMs: row["finished_at_ms"],
            outcome: outcome,
            savedFileBookmark: row["saved_bookmark"]
        )
    }
}
