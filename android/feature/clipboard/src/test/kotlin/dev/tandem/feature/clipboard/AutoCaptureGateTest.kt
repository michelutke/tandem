package dev.tandem.feature.clipboard

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** ADR-007 toggle gating, no-session no-op and debounce. Plain JUnit5. */
class AutoCaptureGateTest {
    private var enabled = true
    private var session = true
    private var now = 10_000L
    private val gate = AutoCaptureGate({ enabled }, { session }, { now }, debounceMillis = 1_000)

    @Test
    fun tryAcquire_settingOff_isFalse() {
        enabled = false

        assertFalse(gate.tryAcquire())
    }

    @Test
    fun tryAcquire_noLiveSession_isFalse() {
        session = false

        assertFalse(gate.tryAcquire())
    }

    @Test
    fun tryAcquire_enabledWithSession_isTrue() {
        assertTrue(gate.tryAcquire())
    }

    @Test
    fun tryAcquire_withinDebounceWindow_isFalse() {
        gate.tryAcquire()
        now += 999

        assertFalse(gate.tryAcquire())
    }

    @Test
    fun tryAcquire_afterDebounceWindow_isTrue() {
        gate.tryAcquire()
        now += 1_000

        assertTrue(gate.tryAcquire())
    }

    @Test
    fun tryAcquire_blockedAttempt_doesNotStartDebounce() {
        enabled = false
        gate.tryAcquire()
        enabled = true

        assertTrue(gate.tryAcquire())
    }
}
