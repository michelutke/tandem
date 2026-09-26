package dev.tandem.core.storage.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * A single typed user preference: the underlying Preferences DataStore key plus the value
 * returned when the key has never been set (E13-04 acceptance: "get of an absent key returns the
 * declared default").
 */
data class SettingsKey<T>(
    val preferencesKey: Preferences.Key<T>,
    val default: T,
)

/**
 * DataStore-backed settings store for non-trust user preferences (E13-04). Scaffold only: a
 * typed get/set API over Preferences DataStore. Concrete preference keys (e.g. the Phase 3
 * per-app notification filters) are declared by their owning feature, not here.
 */
class SettingsStore(
    private val dataStore: DataStore<Preferences>,
) {
    fun <T> get(key: SettingsKey<T>): Flow<T> =
        dataStore.data.map { preferences -> preferences[key.preferencesKey] ?: key.default }

    suspend fun <T> set(
        key: SettingsKey<T>,
        value: T,
    ) {
        dataStore.edit { preferences -> preferences[key.preferencesKey] = value }
    }
}
