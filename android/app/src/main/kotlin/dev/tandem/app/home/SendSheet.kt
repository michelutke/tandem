package dev.tandem.app.home

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.TandemBottomSheet

/**
 * "Send to Mac" sheet (ui-spec.md §7.2 #280 #261), opened by the Home cookie FAB (E20-17):
 * clipboard and file picker entry points.
 */
@OptIn(ExperimentalMaterial3Api::class)
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
        TextButton(onClick = onSendClipboard) {
            Text(text = "Send clipboard to Mac", style = TandemType.rowTitle)
        }
        TextButton(onClick = onSendFiles) {
            Text(text = "Send files to Mac", style = TandemType.rowTitle)
        }
    }
}
