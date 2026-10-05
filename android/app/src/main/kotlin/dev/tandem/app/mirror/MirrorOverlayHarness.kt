package dev.tandem.app.mirror

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import dev.tandem.app.di.AppClock
import dev.tandem.feature.mirror.CaptureSource
import dev.tandem.feature.mirror.TimestampOverlayCaptureSource
import java.io.File

/**
 * E61-08 harness: only a debuggable build with the marker file (`adb shell run-as dev.tandem touch
 * files/mirror-overlay`) burns the timestamp overlay into the mirrored frames.
 */
object MirrorOverlayHarness {
    private const val OVERLAY_MARKER_FILE = "mirror-overlay"

    fun wrap(
        context: Context,
        capture: CaptureSource,
        width: Int,
        height: Int,
    ): CaptureSource =
        if (isEnabled(context)) {
            TimestampOverlayCaptureSource(
                capture,
                { AppClock.system.millis() },
                width,
                height,
                Handler(Looper.getMainLooper()),
            )
        } else {
            capture
        }

    private fun isEnabled(context: Context): Boolean =
        context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
            File(context.filesDir, OVERLAY_MARKER_FILE).exists()
}
