package dev.tandem.feature.notifications

import android.app.Notification
import android.os.Parcelable
import android.service.notification.StatusBarNotification
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted
import dev.tandem.protocol.v1.Visibility
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
     * a plain mapping over its arguments, as are [appName] and [showSecretContent] (E30-11): a
     * `VISIBILITY_SECRET` notification forwards only [appName] as its title, empty text and no
     * messaging-style senders unless [showSecretContent] is true.
     */
    fun toPosted(
        sbn: StatusBarNotification,
        appVersionCode: Long,
        appName: String = "",
        showSecretContent: Boolean = false,
    ): NotificationPosted {
        val visibility = sbn.notification.visibility.toProtoVisibility()
        if (visibility == Visibility.VISIBILITY_SECRET && !showSecretContent) {
            return notificationPosted {
                key = sbn.key
                packageName = sbn.packageName
                this.appVersionCode = appVersionCode
                title = appName
                text = ""
                this.visibility = visibility
            }
        }
        return notificationPosted {
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
            val messages = messagingStyleMessages(sbn.notification)
            // A MessagingStyle notification's own EXTRA_TEXT is an OS-generated single-line
            // summary (e.g. just the newest message), not one line per message -- the Mac
            // presenter (E30-07) pairs `text`'s lines with `messaging_style_senders`
            // positionally, so `text` must actually BE that newline-joined per-message list
            // whenever senders are present, never the plain summary.
            text =
                if (messages.isEmpty()) {
                    sbn.notification.extras
                        .getCharSequence(Notification.EXTRA_TEXT)
                        ?.toString()
                        .orEmpty()
                } else {
                    messages.joinToString("\n") { it.text }
                }
            messagingStyleSenders.addAll(messages.map { it.sender })
            this.visibility = visibility
        }
    }

    private fun Int.toProtoVisibility(): Visibility =
        when (this) {
            Notification.VISIBILITY_PUBLIC -> Visibility.VISIBILITY_PUBLIC
            Notification.VISIBILITY_SECRET -> Visibility.VISIBILITY_SECRET
            else -> Visibility.VISIBILITY_PRIVATE
        }

    /** Called from the listener's `onNotificationRemoved` callback (E30-02 acceptance criterion 3). */
    fun toDismiss(sbn: StatusBarNotification): NotificationDismiss =
        notificationDismiss {
            key = sbn.key
            origin = NotificationDismiss.Origin.ORIGIN_ANDROID
        }

    private data class MessagingStyleMessage(
        val sender: String,
        val text: String,
    )

    // Reconstructed from the built Notification's own extras (this listener never holds the
    // MessagingStyle instance another app's process built), message order preserved.
    private fun messagingStyleMessages(notification: Notification): List<MessagingStyleMessage> {
        val messages = messagesExtra(notification) ?: emptyArray()
        return Notification.MessagingStyle.Message
            .getMessagesFromBundleArray(messages)
            .map { message ->
                MessagingStyleMessage(
                    sender =
                        message.senderPerson
                            ?.name
                            ?.toString()
                            .orEmpty(),
                    text = message.text?.toString().orEmpty(),
                )
            }
    }

    private fun messagesExtra(notification: Notification): Array<out Parcelable>? =
        notification.extras.getParcelableArray(Notification.EXTRA_MESSAGES, Parcelable::class.java)
}
