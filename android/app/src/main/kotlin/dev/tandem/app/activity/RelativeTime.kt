package dev.tandem.app.activity

import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** How long ago an Activity event happened, as the feed shows it ("2 min", "1 h", "Yesterday"). */
sealed interface RelativeTime {
    data object Now : RelativeTime

    data class Minutes(
        val count: Long,
    ) : RelativeTime

    data class Hours(
        val count: Long,
    ) : RelativeTime

    data object Yesterday : RelativeTime

    data class Weekday(
        val name: String,
    ) : RelativeTime
}

private val WEEKDAY_FORMAT = DateTimeFormatter.ofPattern("EEE", Locale.ENGLISH)

/** [now] comes from the injected clock; a timestamp in the future counts as [RelativeTime.Now]. */
internal fun relativeTime(
    now: Instant,
    then: Instant,
    zone: ZoneId,
): RelativeTime {
    val nowDay = now.atZone(zone).toLocalDate()
    val thenDay = then.atZone(zone).toLocalDate()
    val elapsed = Duration.between(then, now)
    return when {
        thenDay == nowDay && elapsed.toMinutes() < 1 -> RelativeTime.Now
        thenDay == nowDay && elapsed.toHours() < 1 -> RelativeTime.Minutes(elapsed.toMinutes())
        thenDay == nowDay -> RelativeTime.Hours(elapsed.toHours())
        thenDay == nowDay.minusDays(1) -> RelativeTime.Yesterday
        thenDay.isAfter(nowDay) -> RelativeTime.Now
        else -> RelativeTime.Weekday(WEEKDAY_FORMAT.format(thenDay))
    }
}
