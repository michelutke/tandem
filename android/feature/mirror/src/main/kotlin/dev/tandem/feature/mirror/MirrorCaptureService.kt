package dev.tandem.feature.mirror

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * The capturing foreground service (E61-02). Its manifest entry declares the `mediaProjection`
 * foreground-service type Android 14 requires; capture itself arrives with E61-03.
 */
class MirrorCaptureService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
}
