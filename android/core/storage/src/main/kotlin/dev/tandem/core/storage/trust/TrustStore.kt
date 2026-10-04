package dev.tandem.core.storage.trust

import android.content.Context
import androidx.room.Room
import androidx.sqlite.driver.AndroidSQLiteDriver
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.rotation.PinKind
import dev.tandem.core.storage.rotation.ResolvedPin
import dev.tandem.core.storage.rotation.RotationPinStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.io.File
import java.util.concurrent.TimeUnit

private const val GRACE_PERIOD_DAYS = 7L
private const val PENDING_MAX_AGE_DAYS = 30L

/** Grace pins expire 7 days after the swap (SPEC.md #key-rotation, Grace pin). */
val GRACE_PERIOD_MS: Long = TimeUnit.DAYS.toMillis(GRACE_PERIOD_DAYS)

/** A pending Mac pin never presented within 30 days is purged (SPEC.md #key-rotation, D-34). */
val PENDING_MAX_AGE_MS: Long = TimeUnit.DAYS.toMillis(PENDING_MAX_AGE_DAYS)

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
@Suppress("TooManyFunctions") // one method per trust-store operation, incl. the E70-04 rotation seam.
class TrustStore private constructor(
    private val db: TrustDatabase,
) : RotationPinStore {
    private val dao get() = db.peerRecordDao()

    suspend fun put(record: PeerRecord) = dao.upsert(record.toEntity())

    suspend fun get(fingerprint: SpkiFingerprint): PeerRecord? = dao.getByFingerprint(fingerprint.base64Url)?.toDomain()

    suspend fun list(): List<PeerRecord> = dao.list().map { it.toDomain() }

    /** Reactive [list] (E20-02): emits the current records, then again on every put/delete/unpair. */
    fun observeList(): Flow<List<PeerRecord>> = dao.observeList().map { entities -> entities.map { it.toDomain() } }

    suspend fun delete(fingerprint: SpkiFingerprint) = dao.deleteByFingerprint(fingerprint.base64Url)

    suspend fun unpair(fingerprint: SpkiFingerprint) = delete(fingerprint)

    override suspend fun resolve(
        fingerprint: SpkiFingerprint,
        nowEpochMs: Long,
    ): ResolvedPin? {
        val entity = dao.findByAnyPin(fingerprint.base64Url, nowEpochMs, nowEpochMs - PENDING_MAX_AGE_MS) ?: return null
        val kind =
            when (fingerprint.base64Url) {
                entity.spkiSha256Base64Url -> PinKind.PRIMARY
                entity.graceSpkiSha256Base64Url -> PinKind.GRACE
                else -> PinKind.PENDING
            }
        return ResolvedPin(kind, entity.toDomain())
    }

    override suspend fun isPrimaryOrGrace(
        fingerprint: SpkiFingerprint,
        nowEpochMs: Long,
    ): Boolean = dao.countPrimaryOrGrace(fingerprint.base64Url, nowEpochMs) > 0

    override suspend fun setPending(
        primary: SpkiFingerprint,
        pending: SpkiFingerprint,
        sinceEpochMs: Long,
    ): Boolean = dao.setPending(primary.base64Url, pending.base64Url, sinceEpochMs) > 0

    override suspend fun promotePending(
        pending: SpkiFingerprint,
        graceExpiresAtEpochMs: Long,
    ): Boolean = dao.promotePending(pending.base64Url, graceExpiresAtEpochMs) > 0

    override suspend fun clearGrace(primary: SpkiFingerprint) = dao.clearGrace(primary.base64Url)

    /** Purges grace pins older than 7 days and pending pins older than 30 days, with or without a session. */
    suspend fun purgeExpiredPins(nowEpochMs: Long) {
        dao.purgeExpiredGrace(nowEpochMs)
        dao.purgeExpiredPending(nowEpochMs - PENDING_MAX_AGE_MS)
    }

    fun close() = db.close()

    companion object {
        /** File-backed store; survives process restart (UC-03). */
        @Suppress("SpreadOperator") // Room's addMigrations only has a vararg overload (E13-03).
        fun open(
            context: Context,
            file: File,
        ): TrustStore {
            val db =
                Room
                    .databaseBuilder(context, TrustDatabase::class.java, file.absolutePath)
                    .setDriver(AndroidSQLiteDriver())
                    .addMigrations(*TrustStoreMigrations.ALL)
                    .build()
            return TrustStore(db)
        }

        /** In-memory store, for tests that don't need restart survival. */
        @Suppress("SpreadOperator") // Room's addMigrations only has a vararg overload (E13-03).
        fun openInMemory(context: Context): TrustStore {
            val db =
                Room
                    .inMemoryDatabaseBuilder(context, TrustDatabase::class.java)
                    .setDriver(AndroidSQLiteDriver())
                    .addMigrations(*TrustStoreMigrations.ALL)
                    .build()
            return TrustStore(db)
        }
    }
}
