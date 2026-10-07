@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FloatingToolbarDefaults
import androidx.compose.material3.HorizontalFloatingToolbar
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.ToggleButtonDefaults
import androidx.compose.material3.ToggleButtonShapes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemIcons
import dev.tandem.core.designsystem.TandemMotion
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.tandemAnimateDpAsState

/**
 * The M3E floating toolbar (ui-spec.md §5.2, §4 motion #03): the platform
 * `HorizontalFloatingToolbar`, `ink` container, icon items, the selected item on a wider white
 * pill. When [fab] is given the toolbar renders it beside the pill. Motion comes from the theme's
 * expressive motion scheme.
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
        items.forEach { item -> ToolbarItem(item = item, selected = item == selected, onSelect = onSelect) }
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

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun ToolbarItem(
    item: FloatingToolbarItem,
    selected: Boolean,
    onSelect: (FloatingToolbarItem) -> Unit,
) {
    val horizontalPadding by tandemAnimateDpAsState(
        targetValue = if (selected) TandemSpacing.xxl else TandemSpacing.md,
        label = "ToolbarItemPadding",
    )
    ToggleButton(
        checked = selected,
        onCheckedChange = { onSelect(item) },
        shapes = ToggleButtonShapes(shape = CircleShape, pressedShape = CircleShape, checkedShape = CircleShape),
        colors =
            ToggleButtonDefaults.colors(
                containerColor = TandemColors.ink,
                contentColor = TandemColors.paper,
                checkedContainerColor = TandemColors.paper,
                checkedContentColor = TandemColors.ink,
            ),
        contentPadding = PaddingValues(horizontal = horizontalPadding),
    ) {
        Icon(imageVector = item.icon, contentDescription = item.label)
    }
}

/**
 * The one bottom bar every top-level screen shares (ui-spec.md §5.2): the [FloatingToolbar] and
 * the cookie send FAB, centred above the navigation bar so it never moves between screens.
 */
@Composable
fun TandemBottomBar(
    selected: FloatingToolbarItem,
    onSelect: (FloatingToolbarItem) -> Unit,
    onSend: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.fillMaxWidth().navigationBarsPadding().padding(TandemSpacing.lg),
        contentAlignment = Alignment.Center,
    ) {
        FloatingToolbar(
            items = FloatingToolbarItem.entries,
            selected = selected,
            onSelect = onSelect,
            fab = {
                CookieFab(onClick = onSend) {
                    Icon(imageVector = TandemIcons.send, contentDescription = SEND_LABEL)
                }
            },
        )
    }
}

const val SEND_LABEL = "Send to Mac"

@Preview(showBackground = true)
@Composable
private fun FloatingToolbarPreview() {
    FloatingToolbar(
        items = FloatingToolbarItem.entries,
        selected = FloatingToolbarItem.Home,
        onSelect = {},
    )
}
