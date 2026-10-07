@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.drawCheckMark

/** Test tag on the thumb's check icon, present only while [M3ESwitch] is checked. */
const val M3E_SWITCH_CHECK_ICON_TEST_TAG = "M3ESwitchCheckIcon"

/**
 * Material 3 Expressive switch (ui-spec.md §5.2, §4 motion #02): `ink` track, `signal` thumb that
 * shows a check when on.
 *
 * The platform expressive `Switch` (material3 1.5, D-81) with the `ink` / `signal` colours; its thumb morph
 * and spring are the component's own, so they do not snap under "Remove animations".
 */
@Composable
fun M3ESwitch(
    checked: Boolean,
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Switch(
        checked = checked,
        onCheckedChange = onCheckedChange,
        modifier = modifier,
        enabled = enabled,
        thumbContent =
            if (checked) {
                {
                    Canvas(modifier = Modifier.size(SwitchDefaults.IconSize).testTag(M3E_SWITCH_CHECK_ICON_TEST_TAG)) {
                        drawCheckMark(color = TandemColors.paper)
                    }
                }
            } else {
                null
            },
        colors =
            SwitchDefaults.colors(
                checkedThumbColor = TandemColors.signal,
                checkedTrackColor = TandemColors.ink,
                checkedBorderColor = TandemColors.ink,
                uncheckedThumbColor = TandemColors.paper,
                uncheckedTrackColor = TandemColors.ink.copy(alpha = 0.12f),
                uncheckedBorderColor = TandemColors.line,
            ),
    )
}

@Preview(showBackground = true)
@Composable
private fun M3ESwitchOnPreview() {
    M3ESwitch(checked = true, onCheckedChange = {})
}

@Preview(showBackground = true)
@Composable
private fun M3ESwitchOffPreview() {
    M3ESwitch(checked = false, onCheckedChange = {})
}
