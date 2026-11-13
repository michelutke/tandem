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
import androidx.compose.ui.res.stringResource
import dev.tandem.app.R
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.DotChart
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.TandemScaffold
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

private const val BYTES_PER_KB = 1024L
private const val SECONDS_PER_MINUTE = 60L

/** The Activity tab (E20-18; ui-spec.md §7.2): 7-day dot chart and a metadata-only event list. */
@Composable
fun ActivityScreen(
    entries: List<ActivityEntry>,
    now: Instant,
    modifier: Modifier = Modifier,
    zone: ZoneId = ZoneId.systemDefault(),
) {
    val chart = ActivityChartData.from(entries, now.atZone(zone).toLocalDate(), zone)

    TandemScaffold(
        title = stringResource(R.string.activity_title),
        state = stringResource(R.string.activity_state),
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
                    text = stringResource(R.string.activity_empty),
                    style = TandemType.body,
                    color = TandemColors.ink2,
                    modifier = Modifier.padding(horizontal = TandemSpacing.screenPadding),
                )
            }
            LazyColumn {
                items(entries.sortedByDescending { it.timestamp }) { entry ->
                    ActivityRow(entry = entry, now = now, zone = zone)
                    HairlineRule()
                }
            }
        }
    }
}

@Composable
private fun ActivityRow(
    entry: ActivityEntry,
    now: Instant,
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
            Text(text = stringResource(entry.type.label), style = TandemType.rowTitle, color = TandemColors.ink)
            formatDetail(entry)?.let { Text(text = it, style = TandemType.meta, color = TandemColors.ink) }
        }
        Text(
            text = relativeTimeText(relativeTime(now, entry.timestamp, zone)),
            style = TandemType.meta,
            color = TandemColors.ink,
        )
    }
}

@Composable
private fun relativeTimeText(relative: RelativeTime): String =
    when (relative) {
        RelativeTime.Now -> stringResource(R.string.activity_now)
        is RelativeTime.Minutes -> stringResource(R.string.activity_minutes_ago, relative.count)
        is RelativeTime.Hours -> stringResource(R.string.activity_hours_ago, relative.count)
        RelativeTime.Yesterday -> stringResource(R.string.activity_yesterday)
        is RelativeTime.Weekday -> relative.name
    }

internal fun formatSize(bytes: Long): String =
    when {
        bytes >= BYTES_PER_KB * BYTES_PER_KB * BYTES_PER_KB -> {
            "%.1f GB".format(Locale.ENGLISH, bytes.toDouble() / (BYTES_PER_KB * BYTES_PER_KB * BYTES_PER_KB))
        }

        bytes >= BYTES_PER_KB * BYTES_PER_KB -> {
            "%.1f MB".format(Locale.ENGLISH, bytes.toDouble() / (BYTES_PER_KB * BYTES_PER_KB))
        }

        else -> {
            "${(bytes + BYTES_PER_KB - 1) / BYTES_PER_KB} KB"
        }
    }

@Composable
private fun formatDetail(entry: ActivityEntry): String? =
    when {
        entry.sizeBytes != null -> {
            formatSize(entry.sizeBytes)
        }

        entry.durationSeconds != null -> {
            stringResource(
                R.string.activity_duration,
                entry.durationSeconds / SECONDS_PER_MINUTE,
                entry.durationSeconds % SECONDS_PER_MINUTE,
            )
        }

        else -> {
            null
        }
    }
