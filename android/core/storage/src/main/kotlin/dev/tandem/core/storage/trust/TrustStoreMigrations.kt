package dev.tandem.core.storage.trust

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/**
 * Registry of [Migration]s applied when opening [TrustDatabase] (E13-03). v1 to v2 (E70-04) adds
 * the nullable grace and pending pin columns used by key rotation; existing rows keep them null.
 * See `TrustStoreTest` for the simulated-migration pattern and the committed v1 fixture.
 */
internal object TrustStoreMigrations {
    private val MIGRATION_1_2 =
        object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE peer_record ADD COLUMN graceSpkiSha256Base64Url TEXT")
                db.execSQL("ALTER TABLE peer_record ADD COLUMN graceExpiresAtEpochMs INTEGER")
                db.execSQL("ALTER TABLE peer_record ADD COLUMN pendingSpkiSha256Base64Url TEXT")
                db.execSQL("ALTER TABLE peer_record ADD COLUMN pendingSinceEpochMs INTEGER")
            }
        }

    val ALL: Array<Migration> = arrayOf(MIGRATION_1_2)
}
