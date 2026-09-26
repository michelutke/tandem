package dev.tandem.core.storage.trust

import android.content.Context
import androidx.room.Room
import androidx.sqlite.driver.AndroidSQLiteDriver
import dev.tandem.core.crypto.SpkiFingerprint
import java.io.File

/**
 * Android trust store (F-1.2, E13-02): Room-backed put/get/list/delete keyed only by
 * [SpkiFingerprint] (invariant 3, CLAUDE.md) -- no IP/hostname/deviceId lookup exists.
 *
 * Uses `AndroidSQLiteDriver` (wraps the OS's built-in SQLite, `androidx.sqlite:sqlite-framework`)
 * rather than the E13-01 spike's `BundledSQLiteDriver`: that JNI-compiled driver's Android-variant
 * artifact packages its native library for on-device extraction from an APK, not for loading from
 * a host JVM's `java.library.path`, so it cannot open a database in this module's local unit
 * tests (`UnsatisfiedLinkError: no sqliteJni in java.library.path`) -- a second, independent
 * deviation from the spike's Finding 1 (docs/spikes/trust-store-persistence.md), on top of `Room`'s
 * Android-variant `databaseBuilder`/`inMemoryDatabaseBuilder` requiring a `Context` even with a
 * driver configured (that spike ran a standalone, non-AGP `kotlin("jvm")` module, which resolves
 * different Gradle variants of both `room-runtime` and `sqlite-bundled`). Robolectric shadows the
 * same `android.database.sqlite` framework classes `AndroidSQLiteDriver` wraps, so
 * `RuntimeEnvironment.getApplication()` (E00-20) supplies a working `Context` in
 * `TrustStoreTest`; see the coder's report for E13-02.
 */
class TrustStore private constructor(
    private val db: TrustDatabase,
) {
    private val dao get() = db.peerRecordDao()

    suspend fun put(record: PeerRecord) = dao.upsert(record.toEntity())

    suspend fun get(fingerprint: SpkiFingerprint): PeerRecord? = dao.getByFingerprint(fingerprint.base64Url)?.toDomain()

    suspend fun list(): List<PeerRecord> = dao.list().map { it.toDomain() }

    suspend fun delete(fingerprint: SpkiFingerprint) = dao.deleteByFingerprint(fingerprint.base64Url)

    suspend fun unpair(fingerprint: SpkiFingerprint) = delete(fingerprint)

    fun close() = db.close()

    companion object {
        /** File-backed store; survives process restart (UC-03). */
        fun open(
            context: Context,
            file: File,
        ): TrustStore {
            val db =
                Room
                    .databaseBuilder(context, TrustDatabase::class.java, file.absolutePath)
                    .setDriver(AndroidSQLiteDriver())
                    .build()
            return TrustStore(db)
        }

        /** In-memory store, for tests that don't need restart survival. */
        fun openInMemory(context: Context): TrustStore {
            val db =
                Room
                    .inMemoryDatabaseBuilder(context, TrustDatabase::class.java)
                    .setDriver(AndroidSQLiteDriver())
                    .build()
            return TrustStore(db)
        }
    }
}
