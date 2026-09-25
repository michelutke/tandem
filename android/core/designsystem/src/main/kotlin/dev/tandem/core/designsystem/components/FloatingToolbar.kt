@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemMotion
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.tandemAnimateFloatAsState

/**
 * The M3E floating toolbar (ui-spec.md §5.2, §4 motion #03): the selected item sits on a white
 * pill; hides on scroll down, returns on scroll up (left to callers via `modifier`/visibility).
 *
 * Deviation: `androidx.compose.material3.HorizontalFloatingToolbar` (M3 Expressive) is not present
 * in the pinned material3 1.4.0 build (no `FloatingToolbarKt` class in the resolved
 * `material3-android-1.4.0` aar), so this is a `Surface` + `Row` with the same selection-pill
 * visual, built on `tandemAnimateFloatAsState` so it still honours "Remove animations".
 */
@Composable
fun FloatingToolbar(
    items: List<FloatingToolbarItem>,
    selected: FloatingToolbarItem,
    onSelect: (FloatingToolbarItem) -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(modifier = modifier, shape = TandemShapes.pill, color = TandemColors.ink) {
        Row(modifier = Modifier.padding(TandemSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
            items.forEach { item ->
                val isSelected = item == selected
                val selectionAlpha by tandemAnimateFloatAsState(
                    targetValue = if (isSelected) 1f else 0f,
                    spec = TandemMotion.toolbarSpring,
                )
                Row(
                    modifier =
                        Modifier
                            .padding(horizontal = TandemSpacing.xs)
                            .background(
                                color = TandemColors.paper.copy(alpha = selectionAlpha),
                                shape = TandemShapes.pill,
                            ).clickable { onSelect(item) }
                            .padding(horizontal = TandemSpacing.md, vertical = TandemSpacing.sm),
                ) {
                    Text(
                        text = item.label,
                        style = TandemType.meta,
                        color = if (isSelected) TandemColors.ink else TandemColors.paper,
                    )
                }
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun FloatingToolbarPreview() {
    FloatingToolbar(
        items = FloatingToolbarItem.entries,
        selected = FloatingToolbarItem.Home,
        onSelect = {},
    )
}
