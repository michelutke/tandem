package dev.tandem.core.storage.trust

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
@Suppress("TooManyFunctions") // one query per trust-store operation, incl. the E70-04 rotation writes.
internal interface PeerRecordDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: PeerRecordEntity)

    @Query("SELECT * FROM peer_record WHERE spkiSha256Base64Url = :spkiSha256Base64Url")
    suspend fun getByFingerprint(spkiSha256Base64Url: String): PeerRecordEntity?

    @Query("SELECT * FROM peer_record")
    suspend fun list(): List<PeerRecordEntity>

    // E20-02: reactive seam for TandemService's "stop when the last paired Mac is unpaired"
    // behavior -- Room re-runs this and re-emits on every write to peer_record.
    @Query("SELECT * FROM peer_record")
    fun observeList(): Flow<List<PeerRecordEntity>>

    @Query("DELETE FROM peer_record WHERE spkiSha256Base64Url = :spkiSha256Base64Url")
    suspend fun deleteByFingerprint(spkiSha256Base64Url: String)

    @Query(
        """
        UPDATE peer_record
        SET lastSeenEpochMs = :lastSeenEpochMs, capabilitiesCsv = :capabilitiesCsv
        WHERE spkiSha256Base64Url = :spkiSha256Base64Url
        """,
    )
    suspend fun updateLastSeenAndCapabilities(
        spkiSha256Base64Url: String,
        lastSeenEpochMs: Long,
        capabilitiesCsv: String,
    )

    // E70-04: every rotation write is one UPDATE statement, so a swap is atomic (old or new state,
    // never partial). SQLite evaluates right-hand sides against the pre-update row.
    @Query(
        """
        SELECT * FROM peer_record
        WHERE spkiSha256Base64Url = :fingerprint
           OR (graceSpkiSha256Base64Url = :fingerprint AND graceExpiresAtEpochMs > :nowEpochMs)
           OR (pendingSpkiSha256Base64Url = :fingerprint AND pendingSinceEpochMs > :pendingCutoffEpochMs)
        """,
    )
    suspend fun findByAnyPin(
        fingerprint: String,
        nowEpochMs: Long,
        pendingCutoffEpochMs: Long,
    ): PeerRecordEntity?

    @Query(
        """
        SELECT COUNT(*) FROM peer_record
        WHERE spkiSha256Base64Url = :fingerprint
           OR (graceSpkiSha256Base64Url = :fingerprint AND graceExpiresAtEpochMs > :nowEpochMs)
        """,
    )
    suspend fun countPrimaryOrGrace(
        fingerprint: String,
        nowEpochMs: Long,
    ): Int

    @Query(
        """
        UPDATE peer_record
        SET pendingSpkiSha256Base64Url = :pending, pendingSinceEpochMs = :sinceEpochMs
        WHERE spkiSha256Base64Url = :primary
        """,
    )
    suspend fun setPending(
        primary: String,
        pending: String,
        sinceEpochMs: Long,
    ): Int

    @Query(
        """
        UPDATE peer_record
        SET graceSpkiSha256Base64Url = spkiSha256Base64Url,
            graceExpiresAtEpochMs = :graceExpiresAtEpochMs,
            spkiSha256Base64Url = pendingSpkiSha256Base64Url,
            pendingSpkiSha256Base64Url = NULL,
            pendingSinceEpochMs = NULL
        WHERE pendingSpkiSha256Base64Url = :pending
        """,
    )
    suspend fun promotePending(
        pending: String,
        graceExpiresAtEpochMs: Long,
    ): Int

    @Query(
        """
        UPDATE peer_record
        SET graceSpkiSha256Base64Url = NULL, graceExpiresAtEpochMs = NULL
        WHERE spkiSha256Base64Url = :primary
        """,
    )
    suspend fun clearGrace(primary: String)

    @Query(
        """
        UPDATE peer_record SET graceSpkiSha256Base64Url = NULL, graceExpiresAtEpochMs = NULL
        WHERE graceExpiresAtEpochMs <= :nowEpochMs
        """,
    )
    suspend fun purgeExpiredGrace(nowEpochMs: Long)

    @Query(
        """
        UPDATE peer_record SET pendingSpkiSha256Base64Url = NULL, pendingSinceEpochMs = NULL
        WHERE pendingSinceEpochMs <= :pendingCutoffEpochMs
        """,
    )
    suspend fun purgeExpiredPending(pendingCutoffEpochMs: Long)
}
