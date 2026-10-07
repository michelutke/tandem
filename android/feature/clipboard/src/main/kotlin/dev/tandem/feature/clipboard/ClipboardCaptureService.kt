package dev.tandem.feature.clipboard

import android.accessibilityservice.AccessibilityService
import android.content.Intent
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

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val isCopy =
            CopyEventFilter.isCopyOverlay(event.packageName, event.eventType, event.className, event.text)
        if (isCopy && gate.tryAcquire()) {
            launcher(ClipboardCaptureActivity.autoCaptureIntent(this))
        }
    }

    override fun onInterrupt() = Unit
}
