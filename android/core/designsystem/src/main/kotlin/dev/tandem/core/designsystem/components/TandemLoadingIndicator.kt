@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LoadingIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors

/** The M3E loading indicator in `ink`, for any wait with no known progress. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun TandemLoadingIndicator(modifier: Modifier = Modifier) {
    LoadingIndicator(modifier = modifier, color = TandemColors.ink)
}

@Preview(showBackground = true)
@Composable
private fun TandemLoadingIndicatorPreview() {
    TandemLoadingIndicator()
}
