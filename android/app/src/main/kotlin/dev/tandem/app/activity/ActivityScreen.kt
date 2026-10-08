package dev.tandem.app.activity

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.DotChart
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.TandemScaffold
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val TIME_FORMAT = DateTimeFormatter.ofPattern("EEE HH:mm", Locale.ENGLISH)
private const val BYTES_PER_KB = 1024L
private const val SECONDS_PER_MINUTE = 60L

/** The Activity tab (E20-18; ui-spec.md §7.2): 7-day dot chart and a metadata-only event list. */
@Composable
fun ActivityScreen(
    entries: List<ActivityEntry>,
    today: LocalDate,
    modifier: Modifier = Modifier,
    zone: ZoneId = ZoneId.systemDefault(),
) {
    val chart = ActivityChartData.from(entries, today, zone)

    TandemScaffold(
        title = "Activity.",
        state = "Last 7 days.",
        modifier = modifier,
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            DotChart(
                values = chart.values,
                labels = chart.labels,
                modifier = Modifier.padding(TandemSpacing.screenPadding),
            )
            if (entries.isEmpty()) {
                Text(
                    text = "Nothing synced yet.",
                    style = TandemType.body,
                    color = TandemColors.ink2,
                    modifier = Modifier.padding(horizontal = TandemSpacing.screenPadding),
                )
            }
            LazyColumn {
                items(entries.sortedByDescending { it.timestamp }) { entry ->
                    ActivityRow(entry = entry, zone = zone)
                    HairlineRule()
                }
            }
        }
    }
}

@Composable
private fun ActivityRow(
    entry: ActivityEntry,
    zone: ZoneId,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.rowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = entry.type.label, style = TandemType.rowTitle, color = TandemColors.ink)
            Text(
                text = TIME_FORMAT.format(entry.timestamp.atZone(zone)),
                style = TandemType.metaMono,
                color = TandemColors.ink2,
            )
        }
        formatDetail(entry)?.let { Text(text = it, style = TandemType.metaMono, color = TandemColors.ink2) }
    }
}

private fun formatDetail(entry: ActivityEntry): String? =
    when {
        entry.sizeBytes != null -> {
            "${(entry.sizeBytes + BYTES_PER_KB - 1) / BYTES_PER_KB} KB"
        }

        entry.durationSeconds != null -> {
            "${entry.durationSeconds / SECONDS_PER_MINUTE}m ${entry.durationSeconds % SECONDS_PER_MINUTE}s"
        }

        else -> {
            null
        }
    }
