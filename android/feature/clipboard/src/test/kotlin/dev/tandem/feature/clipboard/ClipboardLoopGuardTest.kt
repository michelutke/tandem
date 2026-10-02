package dev.tandem.feature.clipboard

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** ClipboardLoopGuard E31-08 tests (`docs/planning/backlog/phase-3.yaml` E31-08's `tdd:` list). Plain JUnit5. */
class ClipboardLoopGuardTest {
    private val hashA = byteArrayOf(1, 2, 3)
    private val hashB = byteArrayOf(4, 5, 6)

    @Test
    fun androidLoopGuard_receivedClipRedetected_notSent() {
        val guard = ClipboardLoopGuard()
        guard.recordReceived("macos", hashA)

        assertFalse(guard.shouldSend(byteArrayOf(1, 2, 3)))
        assertFalse(guard.shouldSend(byteArrayOf(1, 2, 3)))
    }

    @Test
    fun androidLoopGuard_newContentAfterReceive_sentImmediately() {
        val guard = ClipboardLoopGuard()
        guard.recordReceived("macos", hashA)

        assertTrue(guard.shouldSend(hashB))
    }

    @Test
    fun androidLoopGuard_receivedAThenLocalBThenLocalA_aSent() {
        val guard = ClipboardLoopGuard()
        guard.recordReceived("macos", hashA)

        assertTrue(guard.shouldSend(hashB))
        assertTrue(guard.shouldSend(hashA))
    }
}
