package dev.tandem.feature.clipboard

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.security.MessageDigest

/** Shared capture decision used by ClipboardCaptureActivity and OverlayCapture. Plain JUnit5. */
class ClipboardCaptureDecisionTest {
    private val loopGuard = ClipboardLoopGuard()
    private val decision = ClipboardCaptureDecision(loopGuard)

    @BeforeEach
    @AfterEach
    fun resetLastSent() {
        LiveClipboardAutoCapture.lastSentHash = null
    }

    private fun clip(
        text: String,
        sensitive: Boolean = false,
    ) = ClipboardClip(text, sensitive)

    @Test
    fun decision_noClip_doesNotSend() {
        assertFalse(decision.shouldSend(null, hasSession = true, isAuto = true))
    }

    @Test
    fun decision_sensitiveClip_doesNotSend() {
        assertFalse(decision.shouldSend(clip("secret", sensitive = true), hasSession = true, isAuto = false))
    }

    @Test
    fun decision_noSession_doesNotSendAndRecordsNothing() {
        assertFalse(decision.shouldSend(clip("a"), hasSession = false, isAuto = true))
        assertTrue(decision.shouldSend(clip("a"), hasSession = true, isAuto = true))
    }

    @Test
    fun decision_manualCapture_sendsRepeatedClip() {
        assertTrue(decision.shouldSend(clip("a"), hasSession = true, isAuto = false))
        assertTrue(decision.shouldSend(clip("a"), hasSession = true, isAuto = false))
    }

    @Test
    fun decision_autoCaptureRepeat_sendsOnlyOnce() {
        assertTrue(decision.shouldSend(clip("a"), hasSession = true, isAuto = true))
        assertFalse(decision.shouldSend(clip("a"), hasSession = true, isAuto = true))
        assertTrue(decision.shouldSend(clip("b"), hasSession = true, isAuto = true))
    }

    @Test
    fun decision_autoCaptureEchoOfMacClip_doesNotSend() {
        loopGuard.recordReceived("macos", MessageDigest.getInstance("SHA-256").digest("from mac".toByteArray()))

        assertFalse(decision.shouldSend(clip("from mac"), hasSession = true, isAuto = true))
    }
}
