package dev.tandem.app.home

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.TandemBottomSheet

/**
 * Placeholder for "Send to Mac" (ui-spec.md §7.2 #280 #261), opened by the Home cookie FAB
 * (E20-17). The real share/send flow is a separate, not-yet-built issue; this is only the
 * minimal sheet shell the FAB needs to open something.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SendSheet(onDismissRequest: () -> Unit) {
    TandemBottomSheet(onDismissRequest = onDismissRequest) {
        Text(
            text = "Send to Mac",
            style = TandemType.rowTitle,
            modifier = Modifier.padding(TandemSpacing.screenPadding),
        )
    }
}
