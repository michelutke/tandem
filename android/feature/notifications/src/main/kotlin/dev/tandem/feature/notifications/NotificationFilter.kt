package dev.tandem.feature.notifications

import android.app.Notification
import android.service.notification.StatusBarNotification

/**
 * E30-03: the default notification filter, applied to every posted notification before it reaches
 * [NotificationMapper] -- a filtered notification is never mapped or forwarded. The rule set is
 * documented in `SYSTEM_NOISE.md` (checked in alongside this class) and referenced from
 * `docs/protocol/SPEC.md`'s NOTIFY section; both must stay in sync with this implementation.
 */
object NotificationFilter {
    private val SYSTEM_NOISE_PACKAGES = setOf("android", "com.android.systemui")

    /** E30-04: whether [packageName] is on this filter's default-deny system-noise list, so
     * [PerAppNotificationFilter] can show the right default toggle state without duplicating the
     * list. */
    fun isSystemNoisePackage(packageName: String): Boolean = packageName in SYSTEM_NOISE_PACKAGES

    fun shouldForward(
        sbn: StatusBarNotification,
        ownPackageName: String,
    ): Boolean = rejectionReason(sbn, ownPackageName) == null

    /** Why the static rules drop [sbn] (a log-safe reason code, never content), or null if they keep it. */
    fun rejectionReason(
        sbn: StatusBarNotification,
        ownPackageName: String,
    ): String? =
        when {
            sbn.packageName == ownPackageName -> "own_app"
            sbn.packageName in SYSTEM_NOISE_PACKAGES -> "system_noise"
            sbn.notification.flags and Notification.FLAG_FOREGROUND_SERVICE != 0 -> "foreground_service"
            sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0 -> "group_summary"
            isMediaStyle(sbn.notification) -> "media_style"
            else -> null
        }

    private fun isMediaStyle(notification: Notification): Boolean =
        notification.extras.getString(Notification.EXTRA_TEMPLATE) == Notification.MediaStyle::class.java.name
}
