package dev.tandem.feature.notifications

import android.content.pm.PackageManager
import android.graphics.drawable.Drawable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.ConcurrentHashMap

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
 *
 * E30-09: [trackedNotifications] keeps the last-posted [StatusBarNotification] for every key this
 * listener forwarded, so [NotificationActionExecutor]'s composition-root wiring (out of this
 * issue's scope, same as E30-10's `startNotificationDismissReader`) can look up the source
 * `Notification.Action`/`PendingIntent` a received `NotificationAction` refers to via
 * [findTrackedNotification]. A notification that never passed [NotificationFilter] is never
 * tracked either -- the Mac never learned its key, so it can never reference it. Entries are
 * removed on every removal regardless of [reason]: the notification is genuinely gone either way,
 * even when the removal itself is this listener's own E30-10 echo.
 *
 * E30-05: [iconSender] follows the same E30-03 filter decision as the notification it rides along
 * with -- a filtered notification is never mapped, so its app's icon is never extracted or sent
 * either (there would be nothing on the Mac to attach it to). Null by default: like [eventSink],
 * the real [IconSender] is wired in by a composition root, out of this issue's scope.
 *
 * E30-11: [showSecretContent] is the same seam idiom, defaulting to opted-out; a composition root
 * wires it to [SecretNotificationPolicy.showContent] so a toggle applies to the next notification.
 */
class TandemNotificationListenerService : NotificationListenerService() {
    internal var eventSink: NotificationEventSink = LiveNotificationEventSink
    internal var notificationCanceller: (String) -> Unit = ::cancelNotification
    internal var notificationFilter: (StatusBarNotification, String) -> Boolean = NotificationFilter::shouldForward
    internal var iconSender: IconSender? = null
        get() = field ?: LiveNotificationListener.iconSender
    internal var showSecretContent: () -> Boolean = { false }

    private val trackedNotifications = ConcurrentHashMap<String, StatusBarNotification>()

    override fun onListenerConnected() {
        LiveNotificationListener.listener = this
    }

    override fun onListenerDisconnected() {
        if (LiveNotificationListener.listener === this) LiveNotificationListener.listener = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!notificationFilter(sbn, packageName)) return
        trackedNotifications[sbn.key] = sbn
        val versionCode = appVersionCode(sbn.packageName)
        val posted = NotificationMapper.toPosted(sbn, versionCode, appLabel(sbn.packageName), showSecretContent())
        eventSink.onNotificationPosted(posted)
        appIcon(sbn.packageName)?.let { icon ->
            iconSender?.onNotificationPosted(sbn.packageName, versionCode, icon, eventSink::onIconData)
        }
    }

    override fun onNotificationRemoved(
        sbn: StatusBarNotification,
        rankingMap: RankingMap,
        reason: Int,
    ) {
        trackedNotifications.remove(sbn.key)
        if (reason == REASON_LISTENER_CANCEL) return
        eventSink.onNotificationDismissed(NotificationMapper.toDismiss(sbn))
    }

    internal fun findTrackedNotification(key: String): StatusBarNotification? = trackedNotifications[key]

    private fun appVersionCode(packageName: String): Long =
        try {
            packageManager.getPackageInfo(packageName, 0).longVersionCode
        } catch (_: PackageManager.NameNotFoundException) {
            0L
        }

    private fun appLabel(packageName: String): String =
        try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0)).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            packageName
        }

    private fun appIcon(packageName: String): Drawable? =
        try {
            packageManager.getApplicationIcon(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
}
