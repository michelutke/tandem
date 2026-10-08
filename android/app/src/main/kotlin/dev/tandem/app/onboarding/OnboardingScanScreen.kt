package dev.tandem.app.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dev.tandem.core.pairing.qr.PairingInvite
import dev.tandem.feature.pairing.scan.ScannerScreen

internal const val ONBOARDING_SCAN_TITLE = "Scan Mac QR"

/**
 * The onboarding sequence's final, non-skippable step (E20-14, UC-02): sequences to E14-10's
 * [ScannerScreen] unmodified rather than duplicating it -- CAMERA is requested only here, only
 * once the user reaches this screen, never earlier in onboarding. Deliberately has no Skip
 * button, the one exception UC-02 calls out for the camera-during-scan screen.
 */
@Composable
fun OnboardingScanScreen(
    onScanAccepted: (PairingInvite) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    onPairWithoutCamera: (() -> Unit)? = null,
) {
    Column(modifier = modifier.fillMaxSize()) {
        Text(text = ONBOARDING_SCAN_TITLE)
        ScannerScreen(
            onScanAccepted = onScanAccepted,
            onCancel = onCancel,
            onPairWithoutCamera = onPairWithoutCamera,
        )
    }
}
