package dev.tandem.spike.trust.room

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction

@Dao
interface PeerRecordDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: PeerRecordEntity)

    @Query("SELECT * FROM peer_record WHERE spkiSha256Hex = :spkiSha256Hex")
    suspend fun getByFingerprint(spkiSha256Hex: String): PeerRecordEntity?

    @Query("SELECT * FROM peer_record")
    suspend fun list(): List<PeerRecordEntity>

    @Query("DELETE FROM peer_record WHERE spkiSha256Hex = :spkiSha256Hex")
    suspend fun deleteByFingerprint(spkiSha256Hex: String)

    /**
     * Atomic pin swap for key rotation (D-34/E70): delete the old fingerprint row and insert the
     * new one inside one Room transaction, so a concurrent reader never observes both, or
     * neither, fingerprint.
     */
    @Transaction
    suspend fun swapPin(oldSpkiSha256Hex: String, newRecord: PeerRecordEntity) {
        deleteByFingerprint(oldSpkiSha256Hex)
        upsert(newRecord)
    }
}
