@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemMotion
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.cookieShape
import dev.tandem.core.designsystem.tandemAnimateFloatAsState

/**
 * The share/send FAB (ui-spec.md §5.2, §4 motion #04): shape-morphs cookie -> circle on press.
 */
@Composable
fun CookieFab(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: @Composable () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val morph by tandemAnimateFloatAsState(
        targetValue = if (pressed) 1f else 0f,
        spec = TandemMotion.cookieFabSpring,
    )

    FloatingActionButton(
        onClick = onClick,
        modifier = modifier,
        shape = cookieShape(morph),
        containerColor = TandemColors.signal,
        contentColor = TandemColors.paper,
        interactionSource = interactionSource,
        content = icon,
    )
}

@Preview(showBackground = true)
@Composable
private fun CookieFabPreview() {
    CookieFab(onClick = {}) {
        // Callers supply their own icon (e.g. from an icon library); this preview avoids taking a
        // new dependency on one just to render a glyph.
        Text(text = "↑", style = TandemType.rowTitle, color = TandemColors.paper)
    }
}
