package dev.tandem.core.storage.trust

import android.content.Context
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import java.io.File

/**
 * TEST-ONLY simulated v2 of [PeerRecordEntity]/[TrustDatabase], used solely to prove the
 * migration pattern the E13-03 acceptance criteria require (a v1-to-v2 change that adds an
 * optional field preserves every record and defaults the new column). Deliberately not a real
 * Room `@Database`/`@Entity` (that would need its own KSP codegen, a new dependency
 * configuration this scaffold does not need) -- it drives the same [Migration] type production
 * migrations use directly against a [SupportSQLiteDatabase], via the same
 * `androidx.sqlite:sqlite-framework` artifact [TrustStore] already depends on. Production stays
 * on [TrustDatabase] at schema v1 with an empty [TrustStoreMigrations] registry.
 */
internal data class SimulatedV2PeerRecordEntity(
    val spkiSha256Base64Url: String,
    val deviceId: String,
    val displayName: String,
    val pairedAtEpochMs: Long,
    val lastSeenEpochMs: Long,
    val capabilitiesCsv: String,
    val additionalData: String,
)

internal val SIMULATED_MIGRATION_1_TO_2 =
    object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "ALTER TABLE peer_record ADD COLUMN additionalData TEXT NOT NULL DEFAULT ''",
            )
        }
    }

internal class SimulatedV2TrustDatabase private constructor(
    private val helper: SupportSQLiteOpenHelper,
) {
    fun list(): List<SimulatedV2PeerRecordEntity> =
        helper.writableDatabase.query("SELECT * FROM peer_record").use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(
                        SimulatedV2PeerRecordEntity(
                            spkiSha256Base64Url =
                                cursor.getString(cursor.getColumnIndexOrThrow("spkiSha256Base64Url")),
                            deviceId = cursor.getString(cursor.getColumnIndexOrThrow("deviceId")),
                            displayName = cursor.getString(cursor.getColumnIndexOrThrow("displayName")),
                            pairedAtEpochMs = cursor.getLong(cursor.getColumnIndexOrThrow("pairedAtEpochMs")),
                            lastSeenEpochMs = cursor.getLong(cursor.getColumnIndexOrThrow("lastSeenEpochMs")),
                            capabilitiesCsv = cursor.getString(cursor.getColumnIndexOrThrow("capabilitiesCsv")),
                            additionalData = cursor.getString(cursor.getColumnIndexOrThrow("additionalData")),
                        ),
                    )
                }
            }
        }

    fun close() = helper.close()

    companion object {
        /** Opens [dbFile], an existing v1 fixture, upgrading it to v2 via [migration]. */
        fun open(
            context: Context,
            dbFile: File,
            migration: Migration,
        ): SimulatedV2TrustDatabase {
            val callback =
                object : SupportSQLiteOpenHelper.Callback(2) {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        error("SimulatedV2TrustDatabase expects an existing v1 fixture file, not a fresh create")
                    }

                    override fun onUpgrade(
                        db: SupportSQLiteDatabase,
                        oldVersion: Int,
                        newVersion: Int,
                    ) {
                        migration.migrate(db)
                    }
                }
            val configuration =
                SupportSQLiteOpenHelper.Configuration
                    .builder(context)
                    .name(dbFile.absolutePath)
                    .callback(callback)
                    .build()
            return SimulatedV2TrustDatabase(FrameworkSQLiteOpenHelperFactory().create(configuration))
        }
    }
}
