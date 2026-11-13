package dev.tandem.app.activity

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class ActivitySizeFormatTest {
    @Test
    fun formatSize_underOneMegabyte_roundsUpToKilobytes() {
        assertEquals("1 KB", formatSize(1))
        assertEquals("12 KB", formatSize(12_000))
    }

    @Test
    fun formatSize_aboveOneMegabyte_showsOneDecimalMegabytes() {
        assertEquals("12.4 MB", formatSize(13_000_000))
    }

    @Test
    fun formatSize_aboveOneGigabyte_showsOneDecimalGigabytes() {
        assertEquals("1.5 GB", formatSize(1_610_612_736))
    }
}
