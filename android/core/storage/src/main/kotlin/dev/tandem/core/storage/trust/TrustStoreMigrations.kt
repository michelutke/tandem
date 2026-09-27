package dev.tandem.core.storage.trust

import androidx.room.migration.Migration

/**
 * Registry of [Migration]s applied when opening [TrustDatabase] (E13-03 scaffold). Empty today --
 * [TrustDatabase] is still schema v1; a real field addition adds its [Migration] here instead of
 * requiring a destructive reinstall. See `TrustStoreTest` for the simulated v1-to-v2 migration
 * that exercises this pattern against a committed v1 fixture without touching production schema.
 */
internal object TrustStoreMigrations {
    val ALL: Array<Migration> = emptyArray()
}
