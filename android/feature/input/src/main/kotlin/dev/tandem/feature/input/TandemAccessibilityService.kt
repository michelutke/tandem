package dev.tandem.feature.input

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * Opt-in input target (E62-02). It only publishes its [RemoteInputTarget] to [LiveRemoteInput]; every
 * input event reaches it through an `InputGate` (invariant 8, E62-11) and the indicator is hidden
 * whenever the service goes away.
 */
class TandemAccessibilityService : AccessibilityService() {
    private var target: RemoteInputTarget? = null

    override fun onServiceConnected() {
        val actions = ServiceAccessibilityActions(this)
        val connected =
            RemoteInputTarget(
                handler = InputActionHandler(actions),
                translator = GestureTranslator(actions),
                indicator = RemoteInputIndicator(AndroidNotificationPresenter(this), AccessibilityOverlayBadge(this)),
            )
        target = connected
        LiveRemoteInput.current = connected
    }

    override fun onUnbind(intent: Intent?): Boolean {
        release()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        release()
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    private fun release() {
        val released = target ?: return
        target = null
        released.indicator.hide()
        if (LiveRemoteInput.current === released) LiveRemoteInput.current = null
    }
}
