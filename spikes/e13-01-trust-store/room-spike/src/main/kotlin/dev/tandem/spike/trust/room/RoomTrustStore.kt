package dev.tandem.spike.trust.room

import androidx.room.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import java.io.File

/**
 * Prototype trust store on top of Room + the bundled (JNI, host-native) SQLite driver. Keyed by
 * [PeerRecord.spkiSha256Hex] only (invariant 3 -- CLAUDE.md).
 */
class RoomTrustStore private constructor(private val db: TrustDatabase) {
    private val dao get() = db.peerRecordDao()

    suspend fun put(record: PeerRecord) = dao.upsert(record.toEntity())

    suspend fun get(spkiSha256Hex: String): PeerRecord? = dao.getByFingerprint(spkiSha256Hex)?.toDomain()

    suspend fun list(): List<PeerRecord> = dao.list().map { it.toDomain() }

    suspend fun delete(spkiSha256Hex: String) = dao.deleteByFingerprint(spkiSha256Hex)

    suspend fun swapPin(oldSpkiSha256Hex: String, newRecord: PeerRecord) =
        dao.swapPin(oldSpkiSha256Hex, newRecord.toEntity())

    fun close() = db.close()

    companion object {
        /** File-backed store (the real shape); survives process restart. */
        fun open(file: File): RoomTrustStore {
            val db = Room.databaseBuilder<TrustDatabase>(name = file.absolutePath)
                .setDriver(BundledSQLiteDriver())
                .build()
            return RoomTrustStore(db)
        }

        /** In-memory store, for tests that don't care about restart survival. */
        fun openInMemory(): RoomTrustStore {
            val db = Room.inMemoryDatabaseBuilder<TrustDatabase>()
                .setDriver(BundledSQLiteDriver())
                .build()
            return RoomTrustStore(db)
        }
    }
}
