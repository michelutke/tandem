package dev.tandem.app.settings

import androidx.datastore.preferences.core.booleanPreferencesKey
import dev.tandem.core.storage.settings.SettingsKey
import dev.tandem.core.storage.settings.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

/** The four Home switches (ui-spec §7.2 "01-04 feature switches"). */
enum class SyncFeature(
    val label: String,
) {
    Notifications("Notifications"),
    Clipboard("Clipboard"),
    Messages("Messages"),
    Mirroring("Mirroring"),
}

/**
 * Per-feature on/off state behind Home's switches, persisted so it survives restarts and read by
 * the session attacher and the notification listener, so a flip applies without a reconnect.
 * Every feature starts on.
 */
class FeatureToggles(
    private val settings: SettingsStore,
    scope: CoroutineScope,
) {
    private val keys =
        SyncFeature.entries.associateWith { SettingsKey(booleanPreferencesKey("feature_${it.name}_enabled"), true) }

    val states: StateFlow<Map<SyncFeature, Boolean>> =
        combine(SyncFeature.entries.map { feature -> enabled(feature) }) { values ->
            SyncFeature.entries.zip(values).toMap()
        }.stateIn(scope, SharingStarted.Eagerly, SyncFeature.entries.associateWith { true })

    fun enabled(feature: SyncFeature): Flow<Boolean> = settings.get(keys.getValue(feature))

    fun isEnabled(feature: SyncFeature): Boolean = states.value.getValue(feature)

    suspend fun set(
        feature: SyncFeature,
        enabled: Boolean,
    ) {
        settings.set(keys.getValue(feature), enabled)
    }
}
