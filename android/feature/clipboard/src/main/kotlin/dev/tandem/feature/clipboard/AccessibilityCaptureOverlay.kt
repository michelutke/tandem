package dev.tandem.feature.clipboard

import android.content.Context
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.View
import android.view.WindowManager

/**
 * The production [CaptureOverlay]: a 1x1 transparent `TYPE_ACCESSIBILITY_OVERLAY` window, which an
 * accessibility service may add without the draw-over-apps permission. It is focusable so the app
 * counts as focused for clipboard reads, passes touches through (`FLAG_NOT_TOUCH_MODAL`) and uses
 * `FLAG_ALT_FOCUSABLE_IM` so taking focus does not make it the input-method target and the keyboard
 * stays up. No window animation, no insets.
 */
class AccessibilityCaptureOverlay(
    private val context: Context,
) : CaptureOverlay {
    private var view: View? = null

    override fun show(onFocused: () -> Unit) {
        val overlay =
            object : View(context) {
                override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
                    super.onWindowFocusChanged(hasWindowFocus)
                    if (hasWindowFocus) onFocused()
                }
            }
        val params =
            WindowManager
                .LayoutParams(
                    1,
                    1,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM,
                    PixelFormat.TRANSLUCENT,
                ).apply {
                    gravity = Gravity.TOP or Gravity.START
                    windowAnimations = 0
                }
        view = overlay
        context.getSystemService(WindowManager::class.java).addView(overlay, params)
    }

    override fun remove() {
        val overlay = view ?: return
        view = null
        try {
            context.getSystemService(WindowManager::class.java).removeView(overlay)
        } catch (_: IllegalArgumentException) {
            // Already detached by the system.
        }
    }
}
