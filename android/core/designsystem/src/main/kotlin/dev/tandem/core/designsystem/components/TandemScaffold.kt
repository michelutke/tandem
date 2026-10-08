@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing

/**
 * The Android screen frame (ui-spec.md §5.2): status bar and title pair above the content. The
 * floating toolbar and cookie FAB live in the shell's [TandemBottomBar], not per screen.
 */
@Composable
fun TandemScaffold(
    title: String,
    state: String,
    modifier: Modifier = Modifier,
    isError: Boolean = false,
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
        content = content,
    )
}

@Preview(showBackground = true)
@Composable
private fun TandemScaffoldPreview() {
    TandemScaffold(title = "Tandem.", state = "Linked to MacBook Pro.") { padding ->
        Column(modifier = Modifier.padding(padding)) {
            DotRing(value = 43, maxValue = 100, unit = "%")
        }
    }
}
