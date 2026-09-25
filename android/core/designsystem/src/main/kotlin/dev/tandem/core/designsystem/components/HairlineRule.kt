@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.TandemColors

/** A 1 px rule at `ink` 10 % separating hairline rows (ui-spec.md §2 "Hairline rows"). */
@Composable
fun HairlineRule(modifier: Modifier = Modifier) {
    HorizontalDivider(modifier = modifier, thickness = 1.dp, color = TandemColors.line)
}

@Preview(showBackground = true)
@Composable
private fun HairlineRulePreview() {
    HairlineRule()
}
