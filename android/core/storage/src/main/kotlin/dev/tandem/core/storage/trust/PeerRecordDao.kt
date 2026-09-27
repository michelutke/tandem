package dev.tandem.core.storage.trust

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
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
}
