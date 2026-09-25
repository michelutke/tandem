package dev.tandem.core.storage.trust

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(entities = [PeerRecordEntity::class], version = 1, exportSchema = true)
internal abstract class TrustDatabase : RoomDatabase() {
    abstract fun peerRecordDao(): PeerRecordDao
}
