package dev.tandem.app.activity

import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

/** Per-day event counts for the last [DAYS] days ending at `today` (ui-spec.md §7.2 Activity). */
data class ActivityChartData(
    val values: List<Int>,
    val labels: List<String>,
) {
    companion object {
        const val DAYS = 7

        fun from(
            entries: List<ActivityEntry>,
            today: LocalDate,
            zone: ZoneId = ZoneId.systemDefault(),
        ): ActivityChartData {
            val days = (DAYS - 1 downTo 0).map { today.minusDays(it.toLong()) }
            val perDay = entries.groupingBy { it.timestamp.atZone(zone).toLocalDate() }.eachCount()
            return ActivityChartData(
                values = days.map { perDay[it] ?: 0 },
                labels = days.map { it.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.ENGLISH) },
            )
        }
    }
}
