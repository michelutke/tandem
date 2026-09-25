@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing

/**
 * The Android screen frame (ui-spec.md §5.2): status bar, title pair, content, the M3E floating
 * toolbar and cookie FAB. Toolbar/FAB are omitted when not supplied (e.g. pairing screens).
 */
@Composable
@Suppress("LongParameterList") // scaffold composes several independent optional slots
fun TandemScaffold(
    title: String,
    state: String,
    modifier: Modifier = Modifier,
    isError: Boolean = false,
    toolbarItems: List<FloatingToolbarItem> = emptyList(),
    selectedToolbarItem: FloatingToolbarItem? = null,
    onToolbarItemSelected: (FloatingToolbarItem) -> Unit = {},
    fab: (@Composable () -> Unit)? = null,
    content: @Composable (PaddingValues) -> Unit,
) {
    Scaffold(
        modifier = modifier,
        containerColor = TandemColors.paper,
        topBar = {
            Column(modifier = Modifier.padding(TandemSpacing.screenPadding)) {
                TitleBlock(title = title, state = state, isError = isError)
            }
        },
        floatingActionButton = { fab?.invoke() },
        bottomBar = {
            if (toolbarItems.isNotEmpty() && selectedToolbarItem != null) {
                FloatingToolbar(
                    items = toolbarItems,
                    selected = selectedToolbarItem,
                    onSelect = onToolbarItemSelected,
                    modifier = Modifier.padding(TandemSpacing.lg),
                )
            }
        },
        content = content,
    )
}

@Preview(showBackground = true)
@Composable
private fun TandemScaffoldPreview() {
    TandemScaffold(
        title = "Tandem.",
        state = "Linked to MacBook Pro.",
        toolbarItems = FloatingToolbarItem.entries,
        selectedToolbarItem = FloatingToolbarItem.Home,
        fab = {
            CookieFab(onClick = {}) {
                Text("+")
            }
        },
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            DotRing(value = 43, maxValue = 100, unit = "%")
        }
    }
}
