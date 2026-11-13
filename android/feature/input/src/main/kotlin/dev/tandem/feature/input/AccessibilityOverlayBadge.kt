package dev.tandem.feature.input

import android.accessibilityservice.AccessibilityService
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.View
import android.view.WindowManager

/**
 * The [ControlPillView] drawn as a TYPE_ACCESSIBILITY_OVERLAY, which sits above every
 * TYPE_APPLICATION_OVERLAY, so another app cannot cover it. Not focusable; only the pill itself takes
 * touches, and its Stop calls [onStop].
 */
class AccessibilityOverlayBadge(
    private val service: AccessibilityService,
    private val onStop: () -> Unit,
) : OverlayBadge {
    private val windowManager = service.getSystemService(WindowManager::class.java)
    private var view: View? = null

    @Volatile
    private var attachedToWindow = false

    private val attachListener =
        object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {
                attachedToWindow = true
            }

            override fun onViewDetachedFromWindow(v: View) {
                attachedToWindow = false
            }
        }

    override fun attach(): Boolean {
        if (view != null) return true
        val badge = ControlPillView(service, onStop)
        badge.addOnAttachStateChangeListener(attachListener)
        val added =
            runCatching { windowManager.addView(badge, layoutParams()) }
                .isSuccess
        if (added) view = badge else badge.removeOnAttachStateChangeListener(attachListener)
        return added
    }

    override fun detach() {
        val current = view ?: return
        view = null
        attachedToWindow = false
        runCatching { windowManager.removeView(current) }
    }

    override fun isAttached(): Boolean = attachedToWindow

    private fun layoutParams() =
        WindowManager
            .LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                y = (TOP_OFFSET_DP * service.resources.displayMetrics.density).toInt()
                title = WINDOW_TITLE
            }

    companion object {
        const val WINDOW_TITLE = "TandemRemoteInputBadge"
        private const val TOP_OFFSET_DP = 32
    }
}
