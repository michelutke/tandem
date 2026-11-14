package dev.tandem.app.activity

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneOffset

class ActivityRelativeTimeTest {
    private val now = Instant.parse("2026-01-10T12:00:00Z")

    private fun relative(then: String) = relativeTime(now, Instant.parse(then), ZoneOffset.UTC)

    @Test
    fun relativeTime_underOneMinute_isNow() {
        assertEquals(RelativeTime.Now, relative("2026-01-10T11:59:30Z"))
    }

    @Test
    fun relativeTime_minutesAgoSameDay_countsMinutes() {
        assertEquals(RelativeTime.Minutes(2), relative("2026-01-10T11:58:00Z"))
        assertEquals(RelativeTime.Minutes(59), relative("2026-01-10T11:01:00Z"))
    }

    @Test
    fun relativeTime_hoursAgoSameDay_countsWholeHours() {
        assertEquals(RelativeTime.Hours(1), relative("2026-01-10T10:30:00Z"))
        assertEquals(RelativeTime.Hours(11), relative("2026-01-10T00:30:00Z"))
    }

    @Test
    fun relativeTime_previousCalendarDay_isYesterdayEvenWithinTwentyFourHours() {
        assertEquals(RelativeTime.Yesterday, relative("2026-01-09T23:30:00Z"))
        assertEquals(RelativeTime.Yesterday, relative("2026-01-09T01:00:00Z"))
    }

    @Test
    fun relativeTime_olderThanYesterday_isTheWeekday() {
        assertEquals(RelativeTime.Weekday("Thu"), relative("2026-01-08T09:00:00Z"))
    }

    @Test
    fun relativeTime_futureTimestamp_isNow() {
        assertEquals(RelativeTime.Now, relative("2026-01-10T12:05:00Z"))
    }
}
