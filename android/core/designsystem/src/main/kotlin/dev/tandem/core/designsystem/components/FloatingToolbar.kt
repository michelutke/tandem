@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FloatingToolbarDefaults
import androidx.compose.material3.HorizontalFloatingToolbar
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.ToggleButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemType

/**
 * The M3E floating toolbar (ui-spec.md §5.2, §4 motion #03): the platform
 * `HorizontalFloatingToolbar`, `ink` container, the selected item on a white pill. When [fab] is
 * given the toolbar renders it beside the pill, which is the Home layout. Motion comes from the
 * theme's expressive motion scheme.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun FloatingToolbar(
    items: List<FloatingToolbarItem>,
    selected: FloatingToolbarItem,
    onSelect: (FloatingToolbarItem) -> Unit,
    modifier: Modifier = Modifier,
    fab: (@Composable () -> Unit)? = null,
) {
    val colors =
        FloatingToolbarDefaults.standardFloatingToolbarColors(
            toolbarContainerColor = TandemColors.ink,
            toolbarContentColor = TandemColors.paper,
        )
    val toolbarItems: @Composable () -> Unit = {
        items.forEach { item ->
            ToggleButton(
                checked = item == selected,
                onCheckedChange = { onSelect(item) },
                colors =
                    ToggleButtonDefaults.colors(
                        containerColor = TandemColors.ink,
                        contentColor = TandemColors.paper,
                        checkedContainerColor = TandemColors.paper,
                        checkedContentColor = TandemColors.ink,
                    ),
            ) {
                Text(text = item.label, style = TandemType.meta)
            }
        }
    }
    if (fab == null) {
        HorizontalFloatingToolbar(expanded = true, modifier = modifier, colors = colors) { toolbarItems() }
    } else {
        HorizontalFloatingToolbar(
            expanded = true,
            floatingActionButton = fab,
            modifier = modifier,
            colors = colors,
        ) { toolbarItems() }
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
