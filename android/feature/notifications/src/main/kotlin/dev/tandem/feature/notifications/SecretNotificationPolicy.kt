package dev.tandem.feature.notifications

import androidx.datastore.preferences.core.booleanPreferencesKey
import dev.tandem.core.storage.settings.SettingsKey
import dev.tandem.core.storage.settings.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

/**
 * E30-11: phone-side opt-in for forwarding the content of `VISIBILITY_SECRET` notifications.
 * Off by default; persisted in [settingsStore] (DataStore, E13-04). [showContent] is an eagerly
 * collected [StateFlow] so toggling it off redacts the very next notification with no reconnect.
 */
class SecretNotificationPolicy(
    private val settingsStore: SettingsStore,
    scope: CoroutineScope,
) {
    val showContent: StateFlow<Boolean> =
        settingsStore
            .get(SHOW_CONTENT_KEY)
            .stateIn(scope, SharingStarted.Eagerly, SHOW_CONTENT_KEY.default)

    suspend fun setShowContent(enabled: Boolean) {
        settingsStore.set(SHOW_CONTENT_KEY, enabled)
    }

    companion object {
        val SHOW_CONTENT_KEY = SettingsKey(booleanPreferencesKey("show_secret_notification_content"), false)
    }
}
