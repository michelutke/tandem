package dev.tandem.feature.notifications

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

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
        items(rows, key = { it.packageName }) { row ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(text = row.label, modifier = Modifier.weight(1f))
                Switch(
                    checked = row.allowed,
                    onCheckedChange = { checked -> onToggle(row.packageName, checked) },
                    modifier = Modifier.testTag("switch_${row.packageName}"),
                )
            }
        }
    }
}
