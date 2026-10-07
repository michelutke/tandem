import Foundation
import GRDB
import TandemCrypto

/// GRDB/SQLite ``ContactsStore`` at `Application Support/Tandem/contacts.sqlite` (E51-04),
/// opened through ``TandemDatabaseFactory`` like ``GrdbSmsStore``. Never logs row content
/// (invariant 7).
public final class GrdbContactsStore: ContactsStore {
    public static let databaseFileName = "contacts.sqlite"

    private let pool: DatabasePool
    private let normalizer: PhoneNumberNormalizer

    private init(pool: DatabasePool, normalizer: PhoneNumberNormalizer) {
        self.pool = pool
        self.normalizer = normalizer
    }

    /// Opens (creating and migrating when needed) the database at `url`.
    public static func open(
        at url: URL,
        normalizer: PhoneNumberNormalizer = PhoneNumberNormalizer()
    ) throws -> GrdbContactsStore {
        GrdbContactsStore(
            pool: try TandemDatabaseFactory.openPool(at: url, migrator: migrator),
            normalizer: normalizer
        )
    }

    /// Opens the database at its default sandbox-container location.
    public static func openDefault(
        normalizer: PhoneNumberNormalizer = PhoneNumberNormalizer()
    ) throws -> GrdbContactsStore {
        try open(at: TandemDatabaseFactory.defaultDatabaseURL(fileName: databaseFileName), normalizer: normalizer)
    }

    public func close() throws {
        try pool.close()
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try database.execute(sql: """
                CREATE TABLE contact (
                    peer TEXT NOT NULL,
                    contact_id TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    photo_thumbnail BLOB NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    PRIMARY KEY (peer, contact_id)
                );
                CREATE TABLE contact_phone (
                    peer TEXT NOT NULL,
                    contact_id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    number TEXT NOT NULL,
                    normalized_e164 TEXT NOT NULL,
                    lookup_key TEXT NOT NULL,
                    PRIMARY KEY (peer, contact_id, position),
                    FOREIGN KEY (peer, contact_id) REFERENCES contact ON DELETE CASCADE
                );
                CREATE INDEX contact_phone_key ON contact_phone (peer, lookup_key);
                CREATE INDEX contact_phone_number ON contact_phone (peer, number);
                CREATE TABLE contact_email (
                    peer TEXT NOT NULL,
                    contact_id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    address TEXT NOT NULL,
                    PRIMARY KEY (peer, contact_id, position),
                    FOREIGN KEY (peer, contact_id) REFERENCES contact ON DELETE CASCADE
                );
                CREATE TABLE contact_cursor (
                    peer TEXT NOT NULL PRIMARY KEY,
                    watermark_ms INTEGER NOT NULL
                );
                """)
        }
        return migrator
    }

    public func watermarkMs(peer: SpkiFingerprint) async throws -> UInt64? {
        try await pool.read { database in
            try Int64.fetchOne(
                database, sql: "SELECT watermark_ms FROM contact_cursor WHERE peer = ?",
                arguments: [peer.hexString]
            ).map { UInt64(bitPattern: $0) }
        }
    }

    public func apply(
        peer: SpkiFingerprint,
        contacts: [ContactRecord],
        deletedContactIds: [String],
        watermarkMs: UInt64?
    ) async throws {
        let peerKey = peer.hexString
        try await pool.write { [normalizer] database in
            for contact in contacts {
                try Self.upsert(contact, peerKey: peerKey, normalizer: normalizer, in: database)
            }
            for contactId in deletedContactIds {
                try database.execute(
                    sql: "DELETE FROM contact WHERE peer = ? AND contact_id = ?",
                    arguments: [peerKey, contactId]
                )
            }
            if let watermarkMs {
                try database.execute(
                    sql: "INSERT OR REPLACE INTO contact_cursor VALUES (?, ?)",
                    arguments: [peerKey, Int64(bitPattern: watermarkMs)]
                )
            }
        }
    }

    public func lookup(peer: SpkiFingerprint, number: String) async throws -> ContactRecord? {
        let key = normalizer.lookupKey(for: number)
        return try await pool.read { database in
            guard let contactId = try String.fetchOne(
                database,
                sql: """
                    SELECT contact_id FROM contact_phone
                    WHERE peer = ? AND (number = ? OR lookup_key = ?) ORDER BY contact_id LIMIT 1
                    """,
                arguments: [peer.hexString, number, key]
            ) else { return nil }
            return try Self.contact(contactId, peerKey: peer.hexString, in: database)
        }
    }

    public func contactIds(peer: SpkiFingerprint) async throws -> [String] {
        try await pool.read { database in
            try String.fetchAll(
                database, sql: "SELECT contact_id FROM contact WHERE peer = ? ORDER BY contact_id",
                arguments: [peer.hexString]
            )
        }
    }

    public func allContacts(peer: SpkiFingerprint) async throws -> [ContactRecord] {
        try await pool.read { database in
            let contactIds = try String.fetchAll(
                database, sql: "SELECT contact_id FROM contact WHERE peer = ? ORDER BY contact_id",
                arguments: [peer.hexString]
            )
            return try contactIds.compactMap { try Self.contact($0, peerKey: peer.hexString, in: database) }
        }
    }

    public func purgeAll(peer: SpkiFingerprint) async throws {
        try await pool.write { database in
            for table in ["contact", "contact_cursor"] {
                try database.execute(sql: "DELETE FROM \(table) WHERE peer = ?", arguments: [peer.hexString])
            }
        }
    }

    private static func upsert(
        _ contact: ContactRecord,
        peerKey: String,
        normalizer: PhoneNumberNormalizer,
        in database: Database
    ) throws {
        try database.execute(
            sql: "DELETE FROM contact WHERE peer = ? AND contact_id = ?",
            arguments: [peerKey, contact.contactId]
        )
        try database.execute(
            sql: "INSERT INTO contact VALUES (?, ?, ?, ?, ?)",
            arguments: [
                peerKey, contact.contactId, contact.displayName, contact.photoThumbnail, contact.updatedAtMs
            ]
        )
        for (position, phone) in contact.phoneNumbers.enumerated() {
            try database.execute(
                sql: "INSERT INTO contact_phone VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [
                    peerKey, contact.contactId, position, phone.number, phone.normalizedE164,
                    normalizer.lookupKey(for: phone.number, senderE164: phone.normalizedE164)
                ]
            )
        }
        for (position, address) in contact.emails.enumerated() {
            try database.execute(
                sql: "INSERT INTO contact_email VALUES (?, ?, ?, ?)",
                arguments: [peerKey, contact.contactId, position, address]
            )
        }
    }

    private static func contact(_ contactId: String, peerKey: String, in database: Database) throws -> ContactRecord? {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT display_name, photo_thumbnail, updated_at_ms FROM contact WHERE peer = ? AND contact_id = ?",
            arguments: [peerKey, contactId]
        ) else { return nil }
        let phones = try Row.fetchAll(
            database,
            sql: """
                SELECT number, normalized_e164 FROM contact_phone
                WHERE peer = ? AND contact_id = ? ORDER BY position
                """,
            arguments: [peerKey, contactId]
        ).map { ContactPhoneRecord(number: $0["number"], normalizedE164: $0["normalized_e164"]) }
        let emails = try String.fetchAll(
            database,
            sql: "SELECT address FROM contact_email WHERE peer = ? AND contact_id = ? ORDER BY position",
            arguments: [peerKey, contactId]
        )
        return ContactRecord(
            contactId: contactId,
            displayName: row["display_name"],
            phoneNumbers: phones,
            emails: emails,
            photoThumbnail: row["photo_thumbnail"],
            updatedAtMs: row["updated_at_ms"]
        )
    }
}
