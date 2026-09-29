package dev.tandem.app.home

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.CookieFab
import dev.tandem.core.designsystem.components.DotRing
import dev.tandem.core.designsystem.components.FloatingToolbarItem
import dev.tandem.core.designsystem.components.M3ESwitch
import dev.tandem.core.designsystem.components.TandemScaffold

/** Placeholder labels for Home's numbered feature switches (ui-spec.md §7.2 "01-04 feature switches"). */
private val FEATURE_SWITCH_LABELS =
    listOf("Notifications", "Clipboard", "Find phone", "Mirroring")

/**
 * The Home screen (E20-17; ui-spec.md §6, §7.2): TitleBlock, the ring (§6), numbered feature
 * switches, the M3E floating toolbar and the cookie share FAB. Trust failures are handled by the
 * caller: see [HomeViewModel.isBlocked] and [BlockedScreen].
 */
@Composable
@Suppress("LongParameterList") // screen composes several independent, testable slots
fun HomeScreen(
    statusLine: String,
    ringState: HomeRingState,
    selectedToolbarItem: FloatingToolbarItem,
    onToolbarItemSelected: (FloatingToolbarItem) -> Unit,
    modifier: Modifier = Modifier,
) {
    var showSendSheet by remember { mutableStateOf(false) }
    val ring = ringState.toDotRingContent()

    TandemScaffold(
        title = "Tandem.",
        state = statusLine,
        modifier = modifier,
        toolbarItems = FloatingToolbarItem.entries,
        selectedToolbarItem = selectedToolbarItem,
        onToolbarItemSelected = onToolbarItemSelected,
        fab = {
            CookieFab(onClick = { showSendSheet = true }) {
                Text(text = "↑", style = TandemType.rowTitle, color = TandemColors.paper)
            }
        },
    ) { padding ->
        HomeContent(padding = padding, ring = ring)
    }

    if (showSendSheet) {
        SendSheet(onDismissRequest = { showSendSheet = false })
    }
}

@Composable
private fun HomeContent(
    padding: PaddingValues,
    ring: DotRingContent,
) {
    Column(
        modifier = Modifier.padding(padding).fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        DotRing(
            value = ring.value,
            maxValue = ring.maxValue,
            unit = ring.unit,
            modifier = Modifier.padding(TandemSpacing.lg),
        )
        FEATURE_SWITCH_LABELS.forEachIndexed { index, label ->
            FeatureSwitchRow(index = index + 1, label = label)
        }
    }
}

@Composable
private fun FeatureSwitchRow(
    index: Int,
    label: String,
) {
    var checked by remember { mutableStateOf(true) }
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.rowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "%02d".format(index),
            style = TandemType.metaMono,
            color = TandemColors.ink2,
            modifier = Modifier.width(28.dp),
        )
        Text(
            text = label,
            style = TandemType.rowTitle,
            color = TandemColors.ink,
            modifier = Modifier.weight(1f),
        )
        M3ESwitch(checked = checked, onCheckedChange = { checked = it })
    }
}
