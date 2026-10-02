package dev.tandem.feature.notifications

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import dev.tandem.protocol.v1.NotificationPosted
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Test-only listener (declared in the androidTest manifest) that maps every companion-app post
 * through [NotificationMapper] in its default opted-out form and records the result.
 */
class CapturingListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName != COMPANION_PACKAGE) return
        captured += NotificationMapper.toPosted(sbn, appVersionCode = 0L, appName = COMPANION_APP_NAME)
    }

    companion object {
        const val COMPANION_PACKAGE = "dev.tandem.companion"
        const val COMPANION_APP_NAME = "Companion"
        val captured = CopyOnWriteArrayList<NotificationPosted>()
    }
}
