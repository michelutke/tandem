package dev.tandem.feature.clipboard

import dev.tandem.core.transport.TandemSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A 1x1 focusable window the capture waits on; [show] reports once it has window focus. */
interface CaptureOverlay {
    fun show(onFocused: () -> Unit)

    fun remove()
}

/**
 * Auto-capture without starting an activity (ADR-007, D-82): shows [overlay], reads the clipboard
 * the moment it gains focus (Android only allows a read by the focused app), sends it if
 * [decision] allows, and removes the overlay straight after reading. If focus never arrives the
 * overlay is removed after [timeoutMillis] and nothing is sent. If the overlay cannot be shown the
 * capture ends at once, so the next copy starts a fresh one. [scope] must run on the main thread.
 */
class OverlayCapture(
    private val overlay: CaptureOverlay,
    private val reader: ClipboardReader,
    private val session: () -> TandemSession?,
    private val decision: ClipboardCaptureDecision,
    private val scope: CoroutineScope,
    private val timeoutMillis: Long = DEFAULT_TIMEOUT_MILLIS,
) {
    private var timeout: Job? = null
    private var active = false

    fun start() {
        if (active) return
        active = true
        try {
            overlay.show(::onFocused)
        } catch (
            @Suppress("TooGenericExceptionCaught", "SwallowedException") e: RuntimeException,
        ) {
            finish()
            return
        }
        timeout =
            scope.launch {
                delay(timeoutMillis)
                finish()
            }
    }

    private fun onFocused() {
        if (!active) return
        val clip = reader.currentClip()
        val live = session()
        finish()
        if (live != null && decision.shouldSend(clip, hasSession = true, isAuto = true)) {
            scope.launch { ClipboardSender.send(clip!!.text, live) }
        }
    }

    private fun finish() {
        timeout?.cancel()
        timeout = null
        if (active) overlay.remove()
        active = false
    }

    companion object {
        const val DEFAULT_TIMEOUT_MILLIS = 500L
    }
}
