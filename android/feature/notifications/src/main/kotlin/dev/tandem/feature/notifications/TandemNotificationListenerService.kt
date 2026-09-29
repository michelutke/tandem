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
 * E30-03: every posted notification passes [notificationFilter] before it reaches
 * [NotificationMapper] -- a filtered notification is never mapped or forwarded. Dismissals are not
 * filtered (a filtered notification is never sent, so there is nothing on the Mac to withdraw).
 *
 * [notificationFilter] is the same seam idiom as [eventSink]: an `internal var` defaulting to
 * [NotificationFilter]'s static rules, so a composition root can wire in E30-04's
 * [PerAppNotificationFilter] (whose overrides apply to the next notification with no session
 * reconnect) without this class knowing about DataStore or per-app overrides at all.
 *
 * [notificationCanceller] is the same seam pattern, defaulting to the inherited
 * `cancelNotification(String)`: E30-10's incoming-dismiss reader (`startNotificationDismissReader`)
 * calls it for every macos-origin `NotificationDismiss` it sees off the NOTIFY channel, to cancel
 * that notification locally. That reader is spawned by a composition root (out of this issue's
 * scope, same as the macOS twin `startNotificationPresentationReader`), so nothing in this class
 * dials out to a `TandemSession` itself.
 *
 * E30-10: calling `cancelNotification` re-enters this service's [onNotificationRemoved] with
 * `reason == REASON_LISTENER_CANCEL`. That removal is this listener's own echo of a macos-origin
 * dismiss it already applied, not a fresh user action, so it is never forwarded to [eventSink] --
 * otherwise a Mac dismissal would bounce back to the Mac as a phone dismissal forever.
 */
class TandemNotificationListenerService : NotificationListenerService() {
    internal var eventSink: NotificationEventSink = NotificationEventSink.NoOp
    internal var notificationCanceller: (String) -> Unit = ::cancelNotification
    internal var notificationFilter: (StatusBarNotification, String) -> Boolean = NotificationFilter::shouldForward

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!notificationFilter(sbn, packageName)) return
        eventSink.onNotificationPosted(NotificationMapper.toPosted(sbn, appVersionCode(sbn.packageName)))
    }

    override fun onNotificationRemoved(
        sbn: StatusBarNotification,
        rankingMap: RankingMap,
        reason: Int,
    ) {
        if (reason == REASON_LISTENER_CANCEL) return
        eventSink.onNotificationDismissed(NotificationMapper.toDismiss(sbn))
    }

    private fun appVersionCode(packageName: String): Long =
        try {
            packageManager.getPackageInfo(packageName, 0).longVersionCode
        } catch (_: PackageManager.NameNotFoundException) {
            0L
        }
}
