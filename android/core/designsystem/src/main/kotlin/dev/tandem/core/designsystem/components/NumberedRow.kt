@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType

/**
 * A numbered action or fact row (ui-spec.md §2 "Numbered rows"): `01 02 03` in mono grey, one row
 * per action. Rows are separated by [HairlineRule], not boxes.
 */
@Composable
fun NumberedRow(
    index: Int,
    label: String,
    modifier: Modifier = Modifier,
    trailingMeta: String? = null,
    onClick: (() -> Unit)? = null,
) {
    Row(
        modifier =
            modifier
                .fillMaxWidth()
                .let { if (onClick != null) it.clickable(onClick = onClick) else it }
                .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.rowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "%02d".format(index),
            style = TandemType.metaMono,
            color = TandemColors.ink2,
            modifier = Modifier.width(28.dp),
        )
        Text(
            text = label,
            style = TandemType.rowTitle,
            color = TandemColors.ink,
            modifier = Modifier.weight(1f),
        )
        if (trailingMeta != null) {
            Text(text = trailingMeta, style = TandemType.meta, color = TandemColors.ink2)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun NumberedRowPreview() {
    NumberedRow(index = 1, label = "Send file", onClick = {})
}

@Preview(showBackground = true)
@Composable
private fun NumberedRowWithMetaPreview() {
    NumberedRow(index = 2, label = "Default folder", trailingMeta = "Downloads")
}
