package dev.tandem.app.connection.feature

import android.content.Context
import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.settings.SettingsStore
import dev.tandem.core.transport.TandemSession
import dev.tandem.feature.notifications.IconSender
import dev.tandem.feature.notifications.LiveNotificationListener
import dev.tandem.feature.notifications.NotificationActionExecutor
import dev.tandem.feature.notifications.startNotificationActionReader
import dev.tandem.feature.notifications.startNotificationDismissReader
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.coroutineScope

/**
 * The Mac-to-phone half of NOTIFY (F-5.x): fires `NotificationAction`s through the listener's
 * tracked notifications, cancels notifications the Mac dismissed, and hands the listener an
 * [IconSender] that records sent icons in [settingsStore].
 */
class NotificationInteractionsFeature(
    private val context: Context,
    private val settingsStore: SettingsStore,
    private val dispatcher: CoroutineDispatcher,
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        val iconSender = IconSender(settingsStore, dispatcher)
        LiveNotificationListener.iconSender = iconSender
        try {
            coroutineScope {
                val executor = NotificationActionExecutor(context, LiveNotificationListener::findTracked)
                startNotificationActionReader(this, session, executor)
                startNotificationDismissReader(this, session, LiveNotificationListener::cancel)
            }
        } finally {
            if (LiveNotificationListener.iconSender === iconSender) LiveNotificationListener.iconSender = null
            iconSender.close()
        }
    }
}
