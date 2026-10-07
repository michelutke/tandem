package dev.tandem.app.home

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ButtonGroup
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.TandemBottomSheet

/**
 * "Send to Mac" sheet (ui-spec.md §7.2 #280 #261), opened by the Home cookie FAB (E20-17):
 * clipboard and file picker entry points.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun SendSheet(
    onDismissRequest: () -> Unit,
    onSendClipboard: () -> Unit = {},
    onSendFiles: () -> Unit = {},
) {
    TandemBottomSheet(onDismissRequest = onDismissRequest) {
        Text(
            text = "Send to Mac",
            style = TandemType.rowTitle,
            modifier = Modifier.padding(TandemSpacing.screenPadding),
        )
        ButtonGroup(
            overflowIndicator = { menuState -> ButtonGroupDefaults.OverflowIndicator(menuState) },
            modifier = Modifier.padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.lg),
        ) {
            clickableItem(onClick = onSendClipboard, label = "Send clipboard to Mac")
            clickableItem(onClick = onSendFiles, label = "Send files to Mac")
        }
    }
}
