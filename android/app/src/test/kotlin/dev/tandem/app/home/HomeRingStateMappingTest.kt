package dev.tandem.app.home

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class HomeRingStateMappingTest {
    @Test
    fun ringContent_idle_showsSyncedCountWithThingsLabel() {
        val content = HomeRingState.Idle(itemsSyncedToday = 26, sevenDayAverage = 30).toDotRingContent()

        assertEquals(26, content.value)
        assertEquals("things synced today", content.unit)
    }

    @Test
    fun ringContent_sending42Percent_showsPercentWithSendingLabel() {
        val content = HomeRingState.Transfer(percent = 42, toMac = true).toDotRingContent()

        assertEquals(42, content.value)
        assertEquals(100, content.maxValue)
        assertEquals("Sending to Mac", content.unit)
    }

    @Test
    fun ringContent_receiving_showsReceivingLabel() {
        assertEquals("Receiving from Mac", HomeRingState.Transfer(percent = 5, toMac = false).toDotRingContent().unit)
    }

    @Test
    fun ringContent_transferDone_showsFullRingWithPastTenseLabel() {
        assertEquals("Sent.", HomeRingState.TransferDone(toMac = true).toDotRingContent().unit)
        assertEquals("Received.", HomeRingState.TransferDone(toMac = false).toDotRingContent().unit)
    }
}
