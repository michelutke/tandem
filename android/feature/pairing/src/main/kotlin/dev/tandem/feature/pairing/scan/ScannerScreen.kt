package dev.tandem.feature.pairing.scan

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemRadii
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.pairing.qr.PairingInvite
import dev.tandem.core.pairing.qr.ParseInviteResult
import dev.tandem.core.pairing.qr.QrPayloadParser

/**
 * The Android "Scan" screen (`docs/design/screens/android-pairing-scan.png`, ui-spec.md §7.2):
 * dark surface, "Scan." / "The code on your Mac.", a rounded viewfinder and "Decoded on this
 * phone. Nothing is uploaded." With the camera permission denied it shows
 * [ScannerUiState.CameraPermissionRequired] instead: a Grant button and no skip (UC-02).
 *
 * A frame that survives [ScanResultFilter] and then [QrPayloadParser] calls [onScanAccepted]
 * exactly once; the caller wires that to navigation to the pairing-progress screen. A parse
 * rejection (invalid/used code) is left to E14-17's error mapping — out of this screen's scope.
 *
 * [frameSource] is the CameraX-preview seam (E00-20): the default binds a real camera
 * ([CameraXFrameSource]); Compose `ui:` tests substitute a fake that never touches
 * `androidx.camera`, so they can drive [ScannerUiState.Scanning] under Robolectric with no camera.
 */
@Composable
fun ScannerScreen(
    onScanAccepted: (PairingInvite) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    frameSource: @Composable ((onResult: (ScanResult) -> Unit) -> Unit) =
        { onResult -> CameraXFrameSource(onResult = onResult) },
) {
    val context = LocalContext.current
    var hasCameraPermission by remember {
        mutableStateOf(
            context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED,
        )
    }
    val requestCameraPermission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            hasCameraPermission = granted
        }
    val scanResultFilter = remember { ScanResultFilter() }
    val uiState = if (hasCameraPermission) ScannerUiState.Scanning else ScannerUiState.CameraPermissionRequired

    Surface(modifier = modifier.fillMaxSize(), color = TandemColors.paperDark) {
        when (uiState) {
            ScannerUiState.Scanning -> {
                ScanningContent(
                    frameSource = frameSource,
                    onCancel = onCancel,
                    onFrame = { result -> onFrame(result, scanResultFilter, onScanAccepted) },
                )
            }

            ScannerUiState.CameraPermissionRequired -> {
                CameraPermissionRequiredContent(
                    onGrantCameraPermission = { requestCameraPermission.launch(Manifest.permission.CAMERA) },
                )
            }
        }
    }
}

/** Accept-only pipeline (E14-10 acceptance): a rejected parse is silently left for E14-17. */
private fun onFrame(
    result: ScanResult,
    scanResultFilter: ScanResultFilter,
    onScanAccepted: (PairingInvite) -> Unit,
) {
    val outcome = scanResultFilter.apply(result)
    if (outcome is ScanOutcome.Accept) {
        val parsed = QrPayloadParser.parse(outcome.rawValue)
        if (parsed is ParseInviteResult.Accepted) {
            onScanAccepted(parsed.invite)
        }
    }
}

@Composable
private fun CameraPermissionRequiredContent(
    onGrantCameraPermission: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().padding(TandemSpacing.screenPadding),
    ) {
        Text(text = "Camera needed.", style = TandemType.titleEmphasis, color = TandemColors.inkOnDark)
        Text(text = "Scan the code on your Mac.", style = TandemType.titleState, color = TandemColors.inkOnDark)
        // Deliberately no Skip/Cancel here: UC-02's "every permission screen has a skip path,
        // except camera during scanning" — Grant is the only action.
        Button(
            onClick = onGrantCameraPermission,
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(top = TandemSpacing.xxl),
            colors =
                ButtonDefaults.buttonColors(
                    containerColor = TandemColors.inkOnDark,
                    contentColor = TandemColors.paperDark,
                ),
        ) {
            Text(text = "Grant", style = TandemType.rowTitle)
        }
    }
}

@Composable
private fun ScanningContent(
    frameSource: @Composable ((onResult: (ScanResult) -> Unit) -> Unit),
    onCancel: () -> Unit,
    onFrame: (ScanResult) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().padding(TandemSpacing.screenPadding),
    ) {
        Text(text = "Scan.", style = TandemType.titleEmphasis, color = TandemColors.inkOnDark)
        Text(text = "The code on your Mac.", style = TandemType.titleState, color = TandemColors.inkOnDark)

        Box(
            modifier =
                Modifier
                    .padding(top = TandemSpacing.xxl)
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .clip(RoundedCornerShape(TandemRadii.dialog))
                    .border(
                        border = BorderStroke(2.dp, TandemColors.inkOnDark),
                        shape = RoundedCornerShape(TandemRadii.dialog),
                    ),
        ) {
            frameSource(onFrame)
        }

        Text(
            text = "Decoded on this phone. Nothing is uploaded.",
            style = TandemType.meta,
            color = TandemColors.inkOnDark.copy(alpha = 0.7f),
            modifier = Modifier.padding(top = TandemSpacing.xxl),
        )

        OutlinedButton(
            onClick = onCancel,
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(top = TandemSpacing.lg),
            border = BorderStroke(1.dp, TandemColors.inkOnDark),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = TandemColors.inkOnDark),
        ) {
            Text(text = "Cancel", style = TandemType.rowTitle)
        }
    }
}
