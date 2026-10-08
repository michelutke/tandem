package dev.tandem.feature.pairing.manual

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.PillButtonVariant
import dev.tandem.core.designsystem.components.TandemScaffold
import dev.tandem.core.pairing.ManualPairingAddress

/**
 * "Pair without camera" entry (E73-03, ADR-008, ui-spec "Manual entry"): the owner types the
 * `address:port` the Mac's manual window shows. The mode label is always visible so a manual
 * pairing is never mistaken for QR pairing. The address is only where to dial, never trust.
 */
@Composable
fun ManualPairingEntryScreen(
    onSubmit: (ManualPairingAddress) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var text by remember { mutableStateOf("") }
    val parsed = ManualPairingAddress.parse(text)
    TandemScaffold(
        title = "Pair without camera.",
        state = "Enter the address your Mac shows.",
        modifier = modifier,
    ) { padding ->
        Column(
            modifier = Modifier.padding(padding).padding(horizontal = TandemSpacing.screenPadding),
            verticalArrangement = Arrangement.spacedBy(TandemSpacing.md),
        ) {
            Text(text = "Manual pairing", style = TandemType.meta, color = TandemColors.ink)
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Address and port") },
                placeholder = { Text("192.168.1.10:62747") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            )
            PillButton(text = "Continue", onClick = { parsed?.let(onSubmit) }, enabled = parsed != null)
            PillButton(text = "Cancel", onClick = onCancel, variant = PillButtonVariant.Secondary)
        }
    }
}
