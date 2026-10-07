package dev.tandem.app.home

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.tandem.app.settings.SyncFeature
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.DotRing
import dev.tandem.core.designsystem.components.M3ESwitch
import dev.tandem.core.designsystem.components.TandemScaffold

/**
 * The Home screen (E20-17; ui-spec.md §6, §7.2): TitleBlock, the ring (§6), numbered feature
 * switches. Trust failures are handled by the
 * caller: see [HomeViewModel.isBlocked] and [BlockedScreen].
 */
@Composable
@Suppress("LongParameterList") // screen composes several independent, testable slots
fun HomeScreen(
    statusLine: String,
    ringState: HomeRingState,
    modifier: Modifier = Modifier,
    featureStates: Map<SyncFeature, Boolean> = SyncFeature.entries.associateWith { true },
    onFeatureToggled: (SyncFeature, Boolean) -> Unit = { _, _ -> },
) {
    val ring = ringState.toDotRingContent()

    TandemScaffold(
        title = "Tandem.",
        state = statusLine,
        modifier = modifier,
    ) { padding ->
        HomeContent(padding = padding, ring = ring, featureStates = featureStates, onFeatureToggled = onFeatureToggled)
    }
}

@Composable
private fun HomeContent(
    padding: PaddingValues,
    ring: DotRingContent,
    featureStates: Map<SyncFeature, Boolean>,
    onFeatureToggled: (SyncFeature, Boolean) -> Unit,
) {
    Column(
        modifier = Modifier.padding(padding).fillMaxWidth().verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        DotRing(
            value = ring.value,
            maxValue = ring.maxValue,
            unit = ring.unit,
            modifier = Modifier.padding(TandemSpacing.lg),
        )
        SyncFeature.entries.forEachIndexed { index, feature ->
            FeatureSwitchRow(
                index = index + 1,
                label = feature.label,
                checked = featureStates[feature] ?: true,
                onCheckedChange = { onFeatureToggled(feature, it) },
            )
        }
    }
}

@Composable
private fun FeatureSwitchRow(
    index: Int,
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
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
        M3ESwitch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
