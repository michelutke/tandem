package dev.tandem.feature.clipboard

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Resources
import android.view.accessibility.AccessibilityEvent
import dev.tandem.core.transport.time.SystemElapsedRealtimeSource

/**
 * Opt-in copy detector (ADR-007, D-82). Deliberately separate from the remote-input service: its
 * config requests no gestures, no window content and only window-state events from System UI, so it
 * cannot inject input and never reads other apps' screens. On a detected copy overlay it starts the
 * transparent [ClipboardCaptureActivity], which reads the clip once it has focus. It does nothing
 * unless the Settings toggle is on and a Mac session is live.
 */
class ClipboardCaptureService : AccessibilityService() {
    internal var gate =
        AutoCaptureGate(
            isEnabled = { LiveClipboardAutoCapture.isEnabled() },
            hasSession = { LiveClipboardSession.current != null },
            clock = SystemElapsedRealtimeSource,
        )
    internal var launcher: (Intent) -> Unit = ::startActivity
    internal var localizedMarkers: () -> List<String> = ::systemUiCopyStrings

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val isCopy =
            CopyEventFilter.isCopyOverlay(
                event.packageName,
                event.eventType,
                event.className,
                event.text,
                localizedMarkers(),
            )
        if (isCopy && gate.tryAcquire()) {
            launcher(ClipboardCaptureActivity.autoCaptureIntent(this))
        }
    }

    override fun onInterrupt() = Unit

    // Resolved per event so a locale change applies without restarting the service.
    @Suppress("DiscouragedApi") // System UI exposes no public API for these labels
    private fun systemUiCopyStrings(): List<String> =
        try {
            val res = packageManager.getResourcesForApplication(CopyEventFilter.SYSTEM_UI_PACKAGE)
            CopyEventFilter.SYSTEM_UI_COPY_STRINGS.mapNotNull { name ->
                val id = res.getIdentifier(name, "string", CopyEventFilter.SYSTEM_UI_PACKAGE)
                if (id == 0) null else res.getString(id)
            }
        } catch (_: PackageManager.NameNotFoundException) {
            emptyList()
        } catch (_: Resources.NotFoundException) {
            emptyList()
        }
}
