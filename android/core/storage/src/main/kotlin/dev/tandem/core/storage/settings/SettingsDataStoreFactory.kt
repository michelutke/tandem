package dev.tandem.core.storage.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import java.io.File

/**
 * Builds the Preferences DataStore backing [SettingsStore] over [file], with its writer
 * coroutine running on the injected [dispatcher] rather than a hard-coded one (seam rule,
 * CLAUDE.md: dispatchers are injected, never `Dispatchers.IO` inline in core modules).
 */
fun createSettingsDataStore(
    file: File,
    dispatcher: CoroutineDispatcher,
): DataStore<Preferences> =
    PreferenceDataStoreFactory.create(
        scope = CoroutineScope(dispatcher + SupervisorJob()),
        produceFile = { file },
    )
