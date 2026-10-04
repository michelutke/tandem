package dev.tandem.feature.notifications

import android.service.notification.StatusBarNotification

/**
 * What the connection orchestrator's notification features reach the system-constructed
 * [TandemNotificationListenerService] through (E20-24): the attached session's [iconSender], and
 * the listener's tracked notifications and canceller while it is bound. Both are inert (null /
 * no-op) when no listener is bound or no session is attached.
 */
object LiveNotificationListener {
    @Volatile
    var iconSender: IconSender? = null

    @Volatile
    internal var listener: TandemNotificationListenerService? = null

    fun findTracked(key: String): StatusBarNotification? = listener?.findTrackedNotification(key)

    fun cancel(key: String) {
        listener?.notificationCanceller?.invoke(key)
    }
}
