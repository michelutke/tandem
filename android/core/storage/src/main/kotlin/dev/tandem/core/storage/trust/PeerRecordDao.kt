package dev.tandem.core.storage.trust

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
internal interface PeerRecordDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: PeerRecordEntity)

    @Query("SELECT * FROM peer_record WHERE spkiSha256Base64Url = :spkiSha256Base64Url")
    suspend fun getByFingerprint(spkiSha256Base64Url: String): PeerRecordEntity?

    @Query("SELECT * FROM peer_record")
    suspend fun list(): List<PeerRecordEntity>

    @Query("DELETE FROM peer_record WHERE spkiSha256Base64Url = :spkiSha256Base64Url")
    suspend fun deleteByFingerprint(spkiSha256Base64Url: String)
}
