package dev.tandem.spike.trust.room

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

/**
 * E13-03 migration scaffold, Room side: a v1 database file (the [PeerRecordEntity] schema as it
 * shipped) is opened by a v2 database declaring an added, defaulted column, through an explicit
 * [Migration] object. Unlike the DataStore side (proto compatibility is automatic), Room requires
 * the migration to be written and registered -- a missing/wrong migration crashes the open
 * instead of silently losing data, which is the trade-off this test is pinning down.
 */
class TrustDatabaseMigrationTest {

    @TempDir
    lateinit var tempDir: File

    @Entity(tableName = "peer_record")
    data class PeerRecordEntityV1(
        @PrimaryKey val spkiSha256Hex: String,
        val deviceId: String,
        val displayName: String,
        val pairedAtEpochMs: Long,
        val lastSeenEpochMs: Long,
        val capabilitiesCsv: String,
    )

    @Dao
    interface PeerRecordDaoV1 {
        @Insert
        suspend fun insert(record: PeerRecordEntityV1)
    }

    @Database(entities = [PeerRecordEntityV1::class], version = 1, exportSchema = false)
    abstract class TrustDatabaseV1 : RoomDatabase() {
        abstract fun dao(): PeerRecordDaoV1
    }

    @Entity(tableName = "peer_record")
    data class PeerRecordEntityV2(
        @PrimaryKey val spkiSha256Hex: String,
        val deviceId: String,
        val displayName: String,
        val pairedAtEpochMs: Long,
        val lastSeenEpochMs: Long,
        val capabilitiesCsv: String,
        val pendingRotation: Boolean,
    )

    @Dao
    interface PeerRecordDaoV2 {
        @Query("SELECT * FROM peer_record")
        suspend fun list(): List<PeerRecordEntityV2>
    }

    @Database(entities = [PeerRecordEntityV2::class], version = 2, exportSchema = false)
    abstract class TrustDatabaseV2 : RoomDatabase() {
        abstract fun dao(): PeerRecordDaoV2
    }

    private val migration1To2 = object : Migration(1, 2) {
        override fun migrate(connection: SQLiteConnection) {
            connection.execSQL(
                "ALTER TABLE peer_record ADD COLUMN pendingRotation INTEGER NOT NULL DEFAULT 0"
            )
        }
    }

    @Test
    fun v1FixtureToSimulatedV2_allRecordsPreservedNewFieldDefaulted() = runTest {
        val dbFile = File(tempDir, "trust.db")

        val v1 = Room.databaseBuilder<TrustDatabaseV1>(name = dbFile.absolutePath)
            .setDriver(BundledSQLiteDriver())
            .build()
        v1.dao().insert(
            PeerRecordEntityV1(
                spkiSha256Hex = "aa",
                deviceId = "mac-1",
                displayName = "Mac",
                pairedAtEpochMs = 100L,
                lastSeenEpochMs = 200L,
                capabilitiesCsv = "notify",
            )
        )
        v1.close()

        val v2 = Room.databaseBuilder<TrustDatabaseV2>(name = dbFile.absolutePath)
            .setDriver(BundledSQLiteDriver())
            .addMigrations(migration1To2)
            .build()
        val records = v2.dao().list()
        v2.close()

        assertEquals(1, records.size)
        val record = records.single()
        assertEquals("aa", record.spkiSha256Hex)
        assertFalse(record.pendingRotation)
    }
}
