@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.drawDotMark
import dev.tandem.core.designsystem.drawHeroDots

/** The purely decorative dot hero on the onboarding welcome screen (ui-spec.md §5.2, §7.2). */
@Composable
fun DotHero(
    modifier: Modifier = Modifier,
    size: Dp = 220.dp,
) {
    Canvas(modifier = modifier.size(size).clearAndSetSemantics {}) {
        drawHeroDots()
    }
}

/** The decorative 3x3 dot mark with a signal centre on the Paired screen (ui-spec.md §7.2). */
@Composable
fun DotMark(
    modifier: Modifier = Modifier,
    size: Dp = 84.dp,
) {
    Canvas(modifier = modifier.size(size).clearAndSetSemantics {}) {
        drawDotMark()
    }
}

@Preview(showBackground = true)
@Composable
private fun DotHeroPreview() {
    DotHero()
}

@Preview(showBackground = true)
@Composable
private fun DotMarkPreview() {
    DotMark()
}
