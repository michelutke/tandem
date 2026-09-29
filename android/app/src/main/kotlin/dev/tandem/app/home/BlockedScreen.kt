package dev.tandem.app.home

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.NumberedRow
import dev.tandem.core.designsystem.components.TitleBlock

/**
 * Replaces the whole Home screen on a trust failure (ui-spec.md §7.2 "Trust error"; §9.3 "Trust
 * failures are red, stop everything, and offer one action"; invariant 5, CLAUDE.md; E12-16, E20-17).
 * [message] is [dev.tandem.app.connection.ConnectionErrorMapper]'s own PIN_MISMATCH/REVOKED text,
 * so the wording matches whatever the phone's other fail-closed surface already shows.
 */
@Composable
fun BlockedScreen(
    message: String,
    onPairAgain: () -> Unit,
    onUnpair: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize()) {
        Column(modifier = Modifier.padding(TandemSpacing.screenPadding)) {
            TitleBlock(title = "Blocked.", state = message, isError = true)
        }
        HairlineRule()
        NumberedRow(index = 1, label = "Pair again", onClick = onPairAgain)
        NumberedRow(index = 2, label = "Unpair", onClick = onUnpair)
    }
}
