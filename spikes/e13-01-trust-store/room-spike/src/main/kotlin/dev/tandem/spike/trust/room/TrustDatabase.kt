package dev.tandem.spike.trust.room

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(entities = [PeerRecordEntity::class], version = 1, exportSchema = true)
abstract class TrustDatabase : RoomDatabase() {
    abstract fun peerRecordDao(): PeerRecordDao
}
