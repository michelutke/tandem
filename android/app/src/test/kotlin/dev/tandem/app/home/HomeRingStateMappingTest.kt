package dev.tandem.app.home

import dev.tandem.app.R
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class HomeRingStateMappingTest {
    @Test
    fun ringContent_idle_showsSyncedCountWithThingsLabel() {
        val content = HomeRingState.Idle(itemsSyncedToday = 15, sevenDayAverage = 30).toDotRingContent()

        assertEquals("15", content.numeral)
        assertEquals(R.string.home_ring_idle, content.labelRes)
        assertEquals(0.5f, content.litFraction)
        assertNull(content.numeralUnit)
    }

    @Test
    fun ringContent_idleAboveAverage_capsAtFull() {
        assertEquals(1f, HomeRingState.Idle(itemsSyncedToday = 90, sevenDayAverage = 30).toDotRingContent().litFraction)
    }

    @Test
    fun ringContent_sending42Percent_showsPercentWithSendingLabel() {
        val content = HomeRingState.Transfer(percent = 42, toMac = true).toDotRingContent()

        assertEquals("42", content.numeral)
        assertEquals("%", content.numeralUnit)
        assertEquals(0.42f, content.litFraction)
        assertEquals(R.string.home_ring_sending, content.labelRes)
    }

    @Test
    fun ringContent_receiving_showsReceivingLabel() {
        val content = HomeRingState.Transfer(percent = 5, toMac = false).toDotRingContent()

        assertEquals(R.string.home_ring_receiving, content.labelRes)
    }

    @Test
    fun ringContent_transferDone_showsFullRingWithPastTenseLabel() {
        assertEquals(R.string.home_ring_sent, HomeRingState.TransferDone(toMac = true).toDotRingContent().labelRes)
        assertEquals(R.string.home_ring_received, HomeRingState.TransferDone(toMac = false).toDotRingContent().labelRes)
        assertEquals(1f, HomeRingState.TransferDone(toMac = true).toDotRingContent().litFraction)
    }

    @Test
    fun ringContent_mirroring_numeralIsMinutesAndSecondsOnAFullRing() {
        val content = HomeRingState.Mirroring(elapsedSeconds = 102).toDotRingContent()

        assertEquals("01:42", content.numeral)
        assertEquals(1f, content.litFraction)
        assertEquals(R.string.home_ring_mirroring, content.labelRes)
    }

    @Test
    fun ringContent_mirroring_signalDotAdvancesWithTheSecond() {
        assertEquals(0.5f, HomeRingState.Mirroring(elapsedSeconds = 90).toDotRingContent().signalFraction)
    }

    @Test
    fun ringContent_ringing_hasNoNumeralAndPulses() {
        val content = HomeRingState.Ringing.toDotRingContent()

        assertEquals("", content.numeral)
        assertTrue(content.pulse)
        assertEquals(R.string.home_ring_ringing, content.labelRes)
    }

    @Test
    fun ringContent_reconnecting_showsSecondsUnitAttemptAndAllUnlit() {
        val content = HomeRingState.Reconnecting(secondsToNextAttempt = 3, attemptNumber = 2).toDotRingContent()

        assertEquals("3", content.numeral)
        assertEquals("s", content.numeralUnit)
        assertEquals(2, content.labelArg)
        assertEquals(0f, content.litFraction)
        assertFalse(content.pulse)
    }
}
