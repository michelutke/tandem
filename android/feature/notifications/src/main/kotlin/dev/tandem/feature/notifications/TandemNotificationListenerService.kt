package dev.tandem.feature.notifications

import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * E30-02: binds as the system notification listener (declared in `:app`'s manifest with
 * `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE`, E00-28 allowlist) and maps every
 * posted/removed notification through [NotificationMapper] to [eventSink].
 *
 * [eventSink] is an `internal var` (not a constructor parameter: the system instantiates this
 * service via a no-arg constructor) so a test can substitute a fake before invoking
 * `onNotificationPosted`/`onNotificationRemoved` directly, the same seam convention as
 * `TandemService.pairedPeerRepositoryFactory` and `BootReceiver.serviceStarterFactory`. The
 * default is a no-op: the real session-facing sink with disconnected buffering is wired in by
 * E30-16.
 *
 * E30-03: every posted notification passes [NotificationFilter] before it reaches
 * [NotificationMapper] -- a filtered notification is never mapped or forwarded. Dismissals are not
 * filtered (a filtered notification is never sent, so there is nothing on the Mac to withdraw).
 */
class TandemNotificationListenerService : NotificationListenerService() {
    internal var eventSink: NotificationEventSink = NotificationEventSink.NoOp

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!NotificationFilter.shouldForward(sbn, packageName)) return
        eventSink.onNotificationPosted(NotificationMapper.toPosted(sbn, appVersionCode(sbn.packageName)))
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        eventSink.onNotificationDismissed(NotificationMapper.toDismiss(sbn))
    }

    private fun appVersionCode(packageName: String): Long =
        try {
            packageManager.getPackageInfo(packageName, 0).longVersionCode
        } catch (_: PackageManager.NameNotFoundException) {
            0L
        }
}
