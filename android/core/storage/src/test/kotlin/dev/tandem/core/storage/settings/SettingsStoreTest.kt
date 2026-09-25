package dev.tandem.core.storage.settings

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import app.cash.turbine.test
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/**
 * E13-04: DataStore-backed settings store scaffold. Runs on plain JUnit5 against a temp-dir
 * Preferences DataStore (datastore-preferences-core is pure JVM, no Robolectric needed).
 *
 * A DataStore is tracked as "active" for its file until the CoroutineScope it was built with is
 * cancelled (see docs/spikes/trust-store-persistence.md gotchas); the reopen test cancels the
 * first store's scope before opening a second one over the same file to model a real restart.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SettingsStoreTest {
    @TempDir
    lateinit var tempDir: File

    @Test
    fun settingsStore_setThenGetAfterReopen_returnsSetValue() =
        runTest {
            val file = File(tempDir, "settings.preferences_pb")
            val key = SettingsKey(booleanPreferencesKey("mirror_enabled"), default = false)

            val firstScope = CoroutineScope(UnconfinedTestDispatcher(testScheduler) + SupervisorJob())
            val firstStore = SettingsStore(PreferenceDataStoreFactory.create(scope = firstScope) { file })
            firstStore.set(key, true)
            firstScope.cancel()

            val secondScope = CoroutineScope(UnconfinedTestDispatcher(testScheduler) + SupervisorJob())
            val secondStore = SettingsStore(PreferenceDataStoreFactory.create(scope = secondScope) { file })

            secondStore.get(key).test {
                assertEquals(true, awaitItem())
                cancelAndIgnoreRemainingEvents()
            }
            secondScope.cancel()
        }

    @Test
    fun settingsStore_getAbsentKey_returnsDeclaredDefault() =
        runTest {
            val file = File(tempDir, "settings.preferences_pb")
            val key = SettingsKey(stringPreferencesKey("display_name"), default = "unset")

            val scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler) + SupervisorJob())
            val store = SettingsStore(PreferenceDataStoreFactory.create(scope = scope) { file })

            store.get(key).test {
                assertEquals("unset", awaitItem())
                cancelAndIgnoreRemainingEvents()
            }
            scope.cancel()
        }

    @Test
    fun createSettingsDataStore_setThenGet_roundTripsOnInjectedDispatcher() =
        runTest {
            val file = File(tempDir, "settings.preferences_pb")
            val key = SettingsKey(booleanPreferencesKey("mirror_enabled"), default = false)
            val store = SettingsStore(createSettingsDataStore(file, UnconfinedTestDispatcher(testScheduler)))

            store.set(key, true)

            store.get(key).test {
                assertEquals(true, awaitItem())
                cancelAndIgnoreRemainingEvents()
            }
        }
}
