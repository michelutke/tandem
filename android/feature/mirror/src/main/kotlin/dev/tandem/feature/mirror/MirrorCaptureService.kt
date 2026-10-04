package dev.tandem.feature.mirror

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

private val mutableForeground = MutableStateFlow(false)

/** True from the moment [MirrorCaptureService] is foreground with the `mediaProjection` type until it is destroyed. */
object MirrorCaptureServiceState {
    val foreground: StateFlow<Boolean> = mutableForeground.asStateFlow()
}

/**
 * The capturing foreground service (E61-02). Its manifest entry declares the `mediaProjection`
 * foreground-service type Android 14 requires; its ongoing notification is the on-phone mirror
 * indicator (E62-11, invariant 8) for as long as the service runs.
 */
class MirrorCaptureService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.mirror_active_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        mutableForeground.value = true
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        mutableForeground.value = false
        super.onDestroy()
    }

    private fun buildNotification(): Notification =
        Notification
            .Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.mirror_active_title))
            .setContentText(getString(R.string.mirror_active_text))
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .build()

    private companion object {
        const val CHANNEL_ID = "tandem_mirror_active"
        const val NOTIFICATION_ID = 4062
    }
}
