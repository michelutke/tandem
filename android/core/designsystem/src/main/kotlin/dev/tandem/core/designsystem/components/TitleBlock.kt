@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemType

/**
 * The title pair anatomy pattern (ui-spec.md §2, §5.2): line 1 is the subject, bold; line 2 is
 * the state, regular and grey (or red for a trust failure). Screen readers announce both lines as
 * one heading, e.g. "Pixel 9, connected." (ui-spec §11).
 */
@Composable
fun TitleBlock(
    title: String,
    state: String,
    modifier: Modifier = Modifier,
    isError: Boolean = false,
) {
    Column(modifier = modifier.semantics(mergeDescendants = true) { heading() }) {
        Text(text = title, style = TandemType.titleEmphasis, color = TandemColors.ink)
        Text(
            text = state,
            style = TandemType.titleState,
            color = if (isError) TandemColors.alert else TandemColors.ink2,
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun TitleBlockConnectedPreview() {
    TitleBlock(title = "Pixel 9.", state = "Connected.")
}

@Preview(showBackground = true)
@Composable
private fun TitleBlockTrustErrorPreview() {
    TitleBlock(title = "Blocked.", state = "The Mac's key changed.", isError = true)
}
