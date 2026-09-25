@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.drawHeroDots

/** The purely decorative dot hero on the onboarding welcome screen (ui-spec.md §5.2, §7.2). */
@Composable
fun DotHero(
    modifier: Modifier = Modifier,
    dotCount: Int = 48,
    size: Dp = 120.dp,
) {
    Canvas(modifier = modifier.size(size)) {
        drawHeroDots(dotCount = dotCount)
    }
}

@Preview(showBackground = true)
@Composable
private fun DotHeroPreview() {
    DotHero()
}
