package dev.tandem.feature.notifications

import android.app.Notification
import android.os.Build
import android.os.Parcelable
import android.service.notification.StatusBarNotification
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted
import dev.tandem.protocol.v1.notificationDismiss
import dev.tandem.protocol.v1.notificationPosted

/**
 * Plain `StatusBarNotification` -> protocol-message mapping for E30-02, kept framework-decoupled
 * from [TandemNotificationListenerService] itself so it is unit-testable under Robolectric
 * (E00-20) without a real listener binding (which is instead covered by an `instrumented:` test,
 * E00-21).
 */
object NotificationMapper {
    /**
     * [appVersionCode] is resolved by the caller (a `PackageManager` lookup on
     * [StatusBarNotification.getPackageName]) rather than looked up here, so this function stays
     * a plain mapping over its arguments.
     */
    fun toPosted(
        sbn: StatusBarNotification,
        appVersionCode: Long,
    ): NotificationPosted =
        notificationPosted {
            // sbn.key is the system-assigned key for this notification, stable across updates of
            // the same notification (same pkg/id/tag/user) -- matches NotificationPosted.key's
            // "phone-assigned, reused by updates" semantics.
            key = sbn.key
            packageName = sbn.packageName
            this.appVersionCode = appVersionCode
            title =
                sbn.notification.extras
                    .getCharSequence(Notification.EXTRA_TITLE)
                    ?.toString()
                    .orEmpty()
            text =
                sbn.notification.extras
                    .getCharSequence(Notification.EXTRA_TEXT)
                    ?.toString()
                    .orEmpty()
            messagingStyleSenders.addAll(messagingStyleSenderNames(sbn.notification))
        }

    /** Called from the listener's `onNotificationRemoved` callback (E30-02 acceptance criterion 3). */
    fun toDismiss(sbn: StatusBarNotification): NotificationDismiss =
        notificationDismiss {
            key = sbn.key
            origin = NotificationDismiss.Origin.ORIGIN_ANDROID
        }

    // Reconstructed from the built Notification's own extras (this listener never holds the
    // MessagingStyle instance another app's process built), message order preserved.
    // Message.getMessagesFromBundleArray is API 30+; minSdk is 29, so API 29 devices get no
    // sender names rather than a crash.
    private fun messagingStyleSenderNames(notification: Notification): List<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val messages = messagesExtra(notification) ?: emptyArray()
        return Notification.MessagingStyle.Message
            .getMessagesFromBundleArray(messages)
            .map {
                it.senderPerson
                    ?.name
                    ?.toString()
                    .orEmpty()
            }
    }

    // Bundle.getParcelableArray(String, Class) is API 33+; the single-arg overload below it is
    // minSdk 29's only option and deprecated only from API 33, so branch on SDK_INT rather than
    // pulling in androidx.core just for BundleCompat.getParcelableArray.
    @Suppress("DEPRECATION")
    private fun messagesExtra(notification: Notification): Array<out Parcelable>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notification.extras.getParcelableArray(Notification.EXTRA_MESSAGES, Parcelable::class.java)
        } else {
            notification.extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        }
}
