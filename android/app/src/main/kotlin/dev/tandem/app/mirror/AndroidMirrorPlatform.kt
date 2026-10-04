package dev.tandem.app.mirror

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Display
import dev.tandem.app.R
import dev.tandem.feature.input.Size
import dev.tandem.feature.mirror.CaptureSource
import dev.tandem.feature.mirror.DisplayChangeSource
import dev.tandem.feature.mirror.DisplayManagerChangeSource
import dev.tandem.feature.mirror.EncoderFactory
import dev.tandem.feature.mirror.MediaCodecEncoderFactory
import dev.tandem.feature.mirror.MediaProjectionCaptureSource
import dev.tandem.feature.mirror.MediaProjectionConsentLauncher
import dev.tandem.feature.mirror.MirrorCaptureService
import dev.tandem.feature.mirror.MirrorCaptureServiceState
import dev.tandem.feature.mirror.ProjectionConsentLauncher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/** Real [MirrorPlatform]: system consent dialog, capture foreground service, MediaProjection and display. */
class AndroidMirrorPlatform(
    private val context: Context,
) : MirrorPlatform {
    private class Grant(
        val resultCode: Int,
        val data: Intent,
    )

    private val projectionManager = context.getSystemService(MediaProjectionManager::class.java)
    private val displayManager = context.getSystemService(DisplayManager::class.java)
    private val notificationManager = context.getSystemService(NotificationManager::class.java)

    @Volatile
    private var grant: Grant? = null

    override val consentLauncher: ProjectionConsentLauncher =
        MediaProjectionConsentLauncher(projectionManager) { consentIntent ->
            context.startActivity(
                Intent(context, MirrorConsentActivity::class.java)
                    .putExtra(MirrorConsentActivity.EXTRA_CONSENT_INTENT, consentIntent)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }

    override fun setConsentListener(listener: ((granted: Boolean) -> Unit)?) {
        MirrorConsentResults.sink =
            listener?.let { notify ->
                { resultCode, data ->
                    grant = if (resultCode == Activity.RESULT_OK && data != null) Grant(resultCode, data) else null
                    notify(grant != null)
                }
            }
    }

    @Suppress("DEPRECATION") // getRealMetrics: the display's physical size, as DisplayManagerChangeSource reports it
    override fun displaySize(): Size {
        val metrics = DisplayMetrics()
        displayManager.getDisplay(Display.DEFAULT_DISPLAY).getRealMetrics(metrics)
        return Size(metrics.widthPixels, metrics.heightPixels)
    }

    override fun encoderFactory(): EncoderFactory = MediaCodecEncoderFactory()

    override fun displayChanges(): DisplayChangeSource =
        DisplayManagerChangeSource(displayManager, Handler(Looper.getMainLooper()))

    override suspend fun startCaptureService(): Boolean {
        context.startForegroundService(Intent(context, MirrorCaptureService::class.java))
        return withTimeoutOrNull(FOREGROUND_TIMEOUT_MILLIS) { MirrorCaptureServiceState.foreground.first { it } } ==
            true
    }

    override fun stopCaptureService() {
        context.stopService(Intent(context, MirrorCaptureService::class.java))
    }

    override fun openCapture(
        width: Int,
        height: Int,
    ): CaptureSource? {
        val consumed = grant
        grant = null
        val projection =
            consumed?.let {
                try {
                    projectionManager.getMediaProjection(it.resultCode, it.data)
                } catch (_: SecurityException) {
                    null
                }
            }
        return projection?.let {
            MediaProjectionCaptureSource(it, width, height, context.resources.displayMetrics.densityDpi)
        }
    }

    override fun showFailure(failure: MirrorFailure) {
        notificationManager.createNotificationChannel(
            NotificationChannel(
                FAILURE_CHANNEL_ID,
                context.getString(R.string.mirror_blocked_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        notificationManager.notify(
            FAILURE_NOTIFICATION_ID,
            Notification
                .Builder(context, FAILURE_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(context.getString(R.string.mirror_blocked_title))
                .setContentText(context.getString(R.string.mirror_blocked_text))
                .setAutoCancel(true)
                .build(),
        )
    }

    private companion object {
        const val FOREGROUND_TIMEOUT_MILLIS = 5_000L
        const val FAILURE_CHANNEL_ID = "tandem_mirror_blocked"
        const val FAILURE_NOTIFICATION_ID = 4063
    }
}
