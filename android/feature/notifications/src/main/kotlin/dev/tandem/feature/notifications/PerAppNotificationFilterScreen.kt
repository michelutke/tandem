package dev.tandem.feature.notifications

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.M3ESwitch

/**
 * E30-04: settings screen listing every installed app ([rows], sourced from
 * [InstalledAppsSource]/[PerAppNotificationFilter] by the composition root) with a per-app
 * Allow/Deny [Switch]. [onToggle] is called with the row's package name and the switch's new
 * checked state; the composition root wires it to [PerAppNotificationFilter.setOverride].
 */
@Composable
fun PerAppNotificationFilterScreen(
    rows: List<PerAppFilterRow>,
    onToggle: (packageName: String, allowed: Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier = modifier.fillMaxSize()) {
        itemsIndexed(rows, key = { _, row -> row.packageName }) { index, row ->
            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.rowVerticalPadding),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "%02d".format(index + 1),
                    style = TandemType.metaMono,
                    color = TandemColors.ink2,
                    modifier = Modifier.width(INDEX_WIDTH),
                )
                Text(
                    text = row.label,
                    style = TandemType.rowTitle,
                    color = TandemColors.ink,
                    modifier = Modifier.weight(1f),
                )
                M3ESwitch(
                    checked = row.allowed,
                    onCheckedChange = { checked -> onToggle(row.packageName, checked) },
                    modifier = Modifier.testTag("switch_${row.packageName}"),
                )
            }
            HairlineRule()
        }
    }
}

private val INDEX_WIDTH = 28.dp
