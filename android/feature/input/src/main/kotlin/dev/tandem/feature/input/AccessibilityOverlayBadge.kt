package dev.tandem.feature.input

import android.accessibilityservice.AccessibilityService
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import java.util.concurrent.ExecutionException
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

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
    private val mainHandler = Handler(Looper.getMainLooper())
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

    override fun attach(): Boolean = onMainThread(false) { attachOnMain() }

    override fun detach() {
        onMainThread(Unit) { detachOnMain() }
    }

    private fun attachOnMain(): Boolean {
        if (view != null) return true
        val badge = ControlPillView(service, onStop)
        badge.addOnAttachStateChangeListener(attachListener)
        val added =
            runCatching { windowManager.addView(badge, layoutParams()) }
                .isSuccess
        if (added) view = badge else badge.removeOnAttachStateChangeListener(attachListener)
        return added
    }

    private fun detachOnMain() {
        val current = view ?: return
        view = null
        attachedToWindow = false
        runCatching { windowManager.removeView(current) }
    }

    // Views may only be created and added on the main thread; the mirror session calls from a worker.
    private fun <T> onMainThread(
        fallback: T,
        block: () -> T,
    ): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()
        val task = FutureTask(block)
        mainHandler.post(task)
        return try {
            task.get(MAIN_THREAD_TIMEOUT_MILLIS, TimeUnit.MILLISECONDS)
        } catch (_: TimeoutException) {
            task.cancel(false)
            fallback
        } catch (_: ExecutionException) {
            fallback
        }
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
        private const val MAIN_THREAD_TIMEOUT_MILLIS = 2_000L
    }
}
