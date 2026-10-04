package dev.tandem.feature.input

import android.accessibilityservice.AccessibilityService
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.TextView

/**
 * Small badge drawn as a TYPE_ACCESSIBILITY_OVERLAY, which sits above every TYPE_APPLICATION_OVERLAY,
 * so another app cannot cover it. Not touchable or focusable.
 */
class AccessibilityOverlayBadge(
    private val service: AccessibilityService,
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
        val badge =
            TextView(service).apply {
                text = service.getString(R.string.remote_input_badge_label)
                setBackgroundColor(BADGE_BACKGROUND)
                setTextColor(BADGE_TEXT)
            }
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
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                title = WINDOW_TITLE
            }

    companion object {
        const val WINDOW_TITLE = "TandemRemoteInputBadge"
        private const val BADGE_BACKGROUND = 0xFFB00020.toInt()
        private const val BADGE_TEXT = 0xFFFFFFFF.toInt()
    }
}
