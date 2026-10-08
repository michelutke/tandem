package dev.tandem.feature.clipboard

import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/** OverlayCapture lifecycle tests with fakes (ADR-007, D-82). Plain JUnit5. */
@OptIn(ExperimentalCoroutinesApi::class)
class OverlayCaptureTest {
    private class FakeOverlay : CaptureOverlay {
        var shown = 0
        var removed = 0
        private var onFocused: (() -> Unit)? = null

        override fun show(onFocused: () -> Unit) {
            shown++
            this.onFocused = onFocused
        }

        override fun remove() {
            removed++
        }

        fun gainFocus() = onFocused?.invoke()
    }

    private val overlay = FakeOverlay()
    private val session = FakeTandemSession()
    private var clip: ClipboardClip? = ClipboardClip("hello", sensitive = false)
    private var live: FakeTandemSession? = session

    @BeforeEach
    fun resetLastSent() {
        LiveClipboardAutoCapture.lastSentHash = null
    }

    private fun TestScope.capture() =
        OverlayCapture(
            overlay,
            { clip },
            { live },
            ClipboardCaptureDecision(ClipboardLoopGuard()),
            this,
            timeoutMillis = 500,
        )

    @Test
    fun overlayCapture_focusGained_readsSendsAndRemoves() =
        runTest(StandardTestDispatcher()) {
            val capture = capture()

            capture.start()
            overlay.gainFocus()
            runCurrent()

            assertEquals(1, overlay.shown)
            assertEquals(1, overlay.removed)
            assertEquals(
                "hello",
                session.sentFrames
                    .single()
                    .clipboardText.text,
            )
        }

    @Test
    fun overlayCapture_focusNeverArrives_removesAfterTimeoutWithoutSending() =
        runTest(StandardTestDispatcher()) {
            val capture = capture()

            capture.start()
            advanceTimeBy(499)
            runCurrent()
            assertEquals(0, overlay.removed)
            advanceTimeBy(1)
            runCurrent()

            assertEquals(1, overlay.removed)
            assertEquals(0, session.sentFrames.size)
        }

    @Test
    fun overlayCapture_focusGained_cancelsTimeoutSoOverlayRemovedOnce() =
        runTest(StandardTestDispatcher()) {
            val capture = capture()

            capture.start()
            overlay.gainFocus()
            advanceTimeBy(1_000)
            runCurrent()

            assertEquals(1, overlay.removed)
        }

    @Test
    fun overlayCapture_sensitiveClip_removesWithoutSending() =
        runTest(StandardTestDispatcher()) {
            clip = ClipboardClip("secret", sensitive = true)
            val capture = capture()

            capture.start()
            overlay.gainFocus()
            runCurrent()

            assertEquals(1, overlay.removed)
            assertEquals(0, session.sentFrames.size)
        }

    @Test
    fun overlayCapture_noSession_removesWithoutSending() =
        runTest(StandardTestDispatcher()) {
            live = null
            val capture = capture()

            capture.start()
            overlay.gainFocus()
            runCurrent()

            assertEquals(1, overlay.removed)
        }

    @Test
    fun overlayCapture_startWhileActive_showsOnlyOneOverlay() =
        runTest(StandardTestDispatcher()) {
            val capture = capture()

            capture.start()
            capture.start()

            assertEquals(1, overlay.shown)
            overlay.gainFocus()
        }
}
