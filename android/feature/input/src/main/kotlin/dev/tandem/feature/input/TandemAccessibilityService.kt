package dev.tandem.feature.input

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/** Opt-in target only (E62-02); input dispatch lands with E62-04/E62-05, gated by invariant 8. */
class TandemAccessibilityService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit
}
