import Foundation
import GRDB
import TandemCrypto

/// GRDB/SQLite ``SmsStore`` at `Application Support/Tandem/sms.sqlite` (E50-09). Holds SMS data
/// only; trust stays in the Keychain. Never logs row content (invariant 7).
public final class GrdbSmsStore: SmsStore {
    public static let databaseFileName = "sms.sqlite"

    private let pool: DatabasePool

    private init(pool: DatabasePool) {
        self.pool = pool
    }

    /// Opens (creating and migrating when needed) the database at `url`.
    public static func open(at url: URL) throws -> GrdbSmsStore {
        GrdbSmsStore(pool: try TandemDatabaseFactory.openPool(at: url, migrator: migrator))
    }

    /// Opens the database at its default sandbox-container location.
    public static func openDefault() throws -> GrdbSmsStore {
        try open(at: TandemDatabaseFactory.defaultDatabaseURL(fileName: databaseFileName))
    }

    public func close() throws {
        try pool.close()
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try database.execute(sql: """
                CREATE TABLE sms_thread (
                    peer TEXT NOT NULL,
                    thread_id INTEGER NOT NULL,
                    address TEXT NOT NULL,
                    snippet TEXT NOT NULL,
                    last_message_at_ms INTEGER NOT NULL,
                    unread_count INTEGER NOT NULL,
                    PRIMARY KEY (peer, thread_id)
                );
                CREATE TABLE sms_message (
                    peer TEXT NOT NULL,
                    id INTEGER NOT NULL,
                    thread_id INTEGER NOT NULL,
                    address TEXT NOT NULL,
                    body TEXT NOT NULL,
                    timestamp_ms INTEGER NOT NULL,
                    type INTEGER NOT NULL,
                    subscription_id INTEGER NOT NULL,
                    delivery_status INTEGER NOT NULL,
                    PRIMARY KEY (peer, id)
                );
                CREATE INDEX sms_message_thread ON sms_message (peer, thread_id, timestamp_ms, id);
                CREATE TABLE sms_outbound (
                    peer TEXT NOT NULL,
                    client_message_id TEXT NOT NULL,
                    thread_id INTEGER NOT NULL,
                    address TEXT NOT NULL,
                    body TEXT NOT NULL,
                    timestamp_ms INTEGER NOT NULL,
                    state TEXT NOT NULL,
                    provider_message_id INTEGER NOT NULL,
                    PRIMARY KEY (peer, client_message_id)
                );
                CREATE TABLE sms_cursor (
                    peer TEXT NOT NULL PRIMARY KEY,
                    high_watermark_id INTEGER NOT NULL,
                    backfill_cursor_id INTEGER NOT NULL,
                    backfill_complete INTEGER NOT NULL
                );
                """)
        }
        return migrator
    }

    public func threads(peer: SpkiFingerprint) async throws -> [SmsThreadRecord] {
        try await pool.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT thread_id, address, snippet, last_message_at_ms, unread_count
                    FROM sms_thread WHERE peer = ? ORDER BY last_message_at_ms DESC, thread_id DESC
                    """,
                arguments: [peer.hexString]
            ).map { row in
                SmsThreadRecord(
                    threadId: row["thread_id"],
                    address: row["address"],
                    snippet: row["snippet"],
                    lastMessageAtMs: row["last_message_at_ms"],
                    unreadCount: row["unread_count"]
                )
            }
        }
    }

    public func messages(peer: SpkiFingerprint, threadId: Int64) async throws -> [SmsMessageRecord] {
        try await pool.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT id, thread_id, address, body, timestamp_ms, type, subscription_id, delivery_status
                    FROM sms_message WHERE peer = ? AND thread_id = ? ORDER BY timestamp_ms, id
                    """,
                arguments: [peer.hexString, threadId]
            ).map { row in
                SmsMessageRecord(
                    id: row["id"],
                    threadId: row["thread_id"],
                    address: row["address"],
                    body: row["body"],
                    timestampMs: row["timestamp_ms"],
                    type: row["type"],
                    subscriptionId: row["subscription_id"],
                    deliveryStatus: row["delivery_status"]
                )
            }
        }
    }

    public func outbound(peer: SpkiFingerprint, threadId: Int64) async throws -> [SmsOutboundRecord] {
        try await pool.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT client_message_id, thread_id, address, body, timestamp_ms, state, provider_message_id
                    FROM sms_outbound WHERE peer = ? AND thread_id = ? ORDER BY timestamp_ms, client_message_id
                    """,
                arguments: [peer.hexString, threadId]
            ).compactMap { row in
                guard let state = SmsOutboundState(rawValue: row["state"]) else { return nil }
                return SmsOutboundRecord(
                    clientMessageId: row["client_message_id"],
                    threadId: row["thread_id"],
                    address: row["address"],
                    body: row["body"],
                    timestampMs: row["timestamp_ms"],
                    state: state,
                    providerMessageId: row["provider_message_id"]
                )
            }
        }
    }

    public func cursors(peer: SpkiFingerprint) async throws -> SmsSyncCursors? {
        try await pool.read { database in
            try Row.fetchOne(
                database,
                sql: "SELECT high_watermark_id, backfill_cursor_id, backfill_complete FROM sms_cursor WHERE peer = ?",
                arguments: [peer.hexString]
            ).map { row in
                SmsSyncCursors(
                    highWatermarkId: row["high_watermark_id"],
                    backfillCursorId: row["backfill_cursor_id"],
                    backfillComplete: row["backfill_complete"]
                )
            }
        }
    }

    public func applyPage(
        peer: SpkiFingerprint,
        threads: [SmsThreadRecord],
        messages: [SmsMessageRecord],
        cursors: SmsSyncCursors
    ) async throws {
        let peerKey = peer.hexString
        try await pool.write { database in
            for thread in threads {
                try database.execute(
                    sql: "INSERT OR REPLACE INTO sms_thread VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [
                        peerKey, thread.threadId, thread.address, thread.snippet,
                        thread.lastMessageAtMs, thread.unreadCount
                    ]
                )
            }
            for message in messages {
                try database.execute(
                    sql: "INSERT OR REPLACE INTO sms_message VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [
                        peerKey, message.id, message.threadId, message.address, message.body,
                        message.timestampMs, message.type, message.subscriptionId, message.deliveryStatus
                    ]
                )
                try database.execute(
                    sql: "DELETE FROM sms_outbound WHERE peer = ? AND provider_message_id = ?",
                    arguments: [peerKey, message.id]
                )
            }
            try database.execute(
                sql: "INSERT OR REPLACE INTO sms_cursor VALUES (?, ?, ?, ?)",
                arguments: [peerKey, cursors.highWatermarkId, cursors.backfillCursorId, cursors.backfillComplete]
            )
        }
    }

    public func insertOutbound(peer: SpkiFingerprint, _ record: SmsOutboundRecord) async throws {
        try await pool.write { database in
            try database.execute(
                sql: "INSERT OR REPLACE INTO sms_outbound VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                arguments: [
                    peer.hexString, record.clientMessageId, record.threadId, record.address, record.body,
                    record.timestampMs, record.state.rawValue, record.providerMessageId
                ]
            )
        }
    }

    public func updateOutbound(
        peer: SpkiFingerprint,
        clientMessageId: String,
        state: SmsOutboundState,
        providerMessageId: Int64
    ) async throws {
        try await pool.write { database in
            try database.execute(
                sql: """
                    UPDATE sms_outbound SET state = ?, provider_message_id = ?
                    WHERE peer = ? AND client_message_id = ?
                    """,
                arguments: [state.rawValue, providerMessageId, peer.hexString, clientMessageId]
            )
            try database.execute(
                sql: """
                    DELETE FROM sms_outbound WHERE peer = ? AND client_message_id = ? AND EXISTS (
                        SELECT 1 FROM sms_message WHERE peer = ? AND id = ?)
                    """,
                arguments: [peer.hexString, clientMessageId, peer.hexString, providerMessageId]
            )
        }
    }

    public func diagnostics(peer: SpkiFingerprint) async throws -> SmsStoreDiagnostics {
        try await pool.read { database in
            SmsStoreDiagnostics(
                threadIds: try Int64.fetchAll(
                    database, sql: "SELECT thread_id FROM sms_thread WHERE peer = ? ORDER BY thread_id",
                    arguments: [peer.hexString]
                ),
                messageIds: try Int64.fetchAll(
                    database, sql: "SELECT id FROM sms_message WHERE peer = ? ORDER BY id",
                    arguments: [peer.hexString]
                ),
                outboundCount: try Int.fetchOne(
                    database, sql: "SELECT COUNT(*) FROM sms_outbound WHERE peer = ?",
                    arguments: [peer.hexString]
                ) ?? 0
            )
        }
    }

    public func purgeAll(peer: SpkiFingerprint) async throws {
        try await pool.write { database in
            for table in ["sms_thread", "sms_message", "sms_outbound", "sms_cursor"] {
                try database.execute(sql: "DELETE FROM \(table) WHERE peer = ?", arguments: [peer.hexString])
            }
        }
    }
}
