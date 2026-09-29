package dev.tandem.feature.notifications

import android.graphics.drawable.Drawable
import androidx.datastore.preferences.core.stringSetPreferencesKey
import com.google.protobuf.ByteString
import dev.tandem.core.storage.settings.SettingsKey
import dev.tandem.core.storage.settings.SettingsStore
import dev.tandem.protocol.v1.IconData
import dev.tandem.protocol.v1.iconData
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * E30-05: on the first notification from a package+versionCode not yet recorded as sent, encodes
 * that app's icon (via [IconEncoder]) and hands the resulting [IconData] to the caller's
 * `onIconData` callback; every later notification from the same package+version is a no-op. An app
 * update (new versionCode) is a different record, so it triggers a fresh send.
 *
 * The sent-record set is persisted via [SettingsStore] (E13-04's DataStore-backed scaffold, the
 * same small-persisted-record convention `SettingsStoreTest` exercises), so it survives a process
 * restart -- a fresh [IconSender] instance over the same store never resends an already-recorded
 * package+version.
 *
 * The record is written as soon as this instance decides to send (before the caller's `onIconData`
 * callback actually reaches the wire): if the session is not connected when the callback fires and
 * the icon is dropped there, this instance will not retry it on a later notification from the same
 * package+version. That tradeoff is out of this issue's scope (its acceptance criteria don't cover
 * offline delivery); E30-16-style buffering for `IconData` would be a follow-up if needed.
 *
 * Owns its own coroutine scope (same seam convention as [NotificationSink]): [close] must be called
 * before a replacement instance takes over the same store.
 */
class IconSender(
    private val settingsStore: SettingsStore,
    dispatcher: CoroutineDispatcher,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)

    fun close() {
        scope.cancel()
    }

    fun onNotificationPosted(
        packageName: String,
        versionCode: Long,
        icon: Drawable,
        onIconData: (IconData) -> Unit,
    ) {
        scope.launch {
            val sent = settingsStore.get(SENT_RECORDS_KEY).first()
            val record = recordKey(packageName, versionCode)
            if (record in sent) return@launch
            settingsStore.set(SENT_RECORDS_KEY, sent + record)
            onIconData(
                iconData {
                    this.packageName = packageName
                    this.versionCode = versionCode
                    pngBytes = ByteString.copyFrom(IconEncoder.encode(icon))
                },
            )
        }
    }

    private companion object {
        val SENT_RECORDS_KEY = SettingsKey(stringSetPreferencesKey("icon_sent_records"), emptySet())

        fun recordKey(
            packageName: String,
            versionCode: Long,
        ): String = "$packageName@$versionCode"
    }
}
