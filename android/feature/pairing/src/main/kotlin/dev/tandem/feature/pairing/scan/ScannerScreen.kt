package dev.tandem.feature.pairing.scan

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.DarkSystemBars
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemRadii
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.pairing.qr.PairingInvite
import dev.tandem.core.pairing.qr.ParseInviteResult
import dev.tandem.core.pairing.qr.QrPayloadParser
import dev.tandem.feature.pairing.R

private const val TANDEM_SCHEME_PREFIX = "tandem://"

/**
 * The Android "Scan" screen (`docs/design/screens/android-pairing-scan.png`, ui-spec.md §7.2):
 * dark edge to edge surface, "Scan." / "The code on your Mac.", a rounded viewfinder and "Decoded on
 * this phone. Nothing is uploaded." With the camera permission denied it shows
 * [ScannerUiState.CameraPermissionRequired] instead: a Grant button and no skip (UC-02).
 *
 * A frame that survives [ScanResultFilter] and then [QrPayloadParser] calls [onScanAccepted]
 * exactly once. A QR that is not a Tandem code, or a Tandem code that fails to parse, shows
 * [ScannerUiState.InvalidCode] ("Not a Tandem code." with a red viewfinder) until Scan again.
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
    onPairWithoutCamera: (() -> Unit)? = null,
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
    var scanResultFilter by remember { mutableStateOf(ScanResultFilter()) }
    var invalidCode by remember { mutableStateOf(false) }
    val uiState =
        when {
            !hasCameraPermission -> ScannerUiState.CameraPermissionRequired
            invalidCode -> ScannerUiState.InvalidCode
            else -> ScannerUiState.Scanning
        }

    DarkSystemBars()
    Surface(modifier = modifier.fillMaxSize(), color = TandemColors.paperDark) {
        Column(modifier = Modifier.fillMaxSize().safeDrawingPadding().padding(TandemSpacing.screenPadding)) {
            when (uiState) {
                ScannerUiState.CameraPermissionRequired -> {
                    CameraPermissionRequiredContent(
                        onGrantCameraPermission = { requestCameraPermission.launch(Manifest.permission.CAMERA) },
                        onPairWithoutCamera = onPairWithoutCamera,
                    )
                }

                else -> {
                    ScanningContent(
                        invalid = uiState == ScannerUiState.InvalidCode,
                        frameSource = frameSource,
                        onCancel = onCancel,
                        onScanAgain = {
                            scanResultFilter = ScanResultFilter()
                            invalidCode = false
                        },
                        onPairWithoutCamera = onPairWithoutCamera,
                        onFrame = { result ->
                            if (!invalidCode && onFrame(result, scanResultFilter, onScanAccepted)) invalidCode = true
                        },
                    )
                }
            }
        }
    }
}

/** Returns true when [result] is a QR that is not a usable Tandem code. */
private fun onFrame(
    result: ScanResult,
    scanResultFilter: ScanResultFilter,
    onScanAccepted: (PairingInvite) -> Unit,
): Boolean {
    val notTandem = result.format == ScanFormat.QR_CODE && !result.rawValue.startsWith(TANDEM_SCHEME_PREFIX)
    val outcome = if (notTandem) ScanOutcome.Ignore else scanResultFilter.apply(result)
    val parsed = (outcome as? ScanOutcome.Accept)?.let { QrPayloadParser.parse(it.rawValue) }
    if (parsed is ParseInviteResult.Accepted) onScanAccepted(parsed.invite)
    return notTandem || parsed is ParseInviteResult.Rejected
}

@Composable
private fun CameraPermissionRequiredContent(
    onGrantCameraPermission: () -> Unit,
    onPairWithoutCamera: (() -> Unit)?,
) {
    Text(
        text = stringResource(R.string.scan_camera_needed_title),
        style = TandemType.titleEmphasis,
        color = TandemColors.inkOnDark,
    )
    Text(
        text = stringResource(R.string.scan_camera_needed_state),
        style = TandemType.titleState,
        color = TandemColors.inkOnDark,
    )
    // Deliberately no Skip/Cancel here: UC-02's "every permission screen has a skip path,
    // except camera during scanning", so Grant is the only action.
    Button(
        onClick = onGrantCameraPermission,
        modifier = Modifier.fillMaxWidth().padding(top = TandemSpacing.xxl),
        shape = TandemShapes.button,
        colors =
            ButtonDefaults.buttonColors(
                containerColor = TandemColors.inkOnDark,
                contentColor = TandemColors.paperDark,
            ),
    ) {
        Text(text = stringResource(R.string.scan_grant), style = TandemType.rowTitle)
    }
    PairWithoutCameraButton(onPairWithoutCamera)
}

@Composable
@Suppress("LongParameterList") // one slot per piece of the scan screen
private fun ColumnScope.ScanningContent(
    invalid: Boolean,
    frameSource: @Composable ((onResult: (ScanResult) -> Unit) -> Unit),
    onCancel: () -> Unit,
    onScanAgain: () -> Unit,
    onPairWithoutCamera: (() -> Unit)?,
    onFrame: (ScanResult) -> Unit,
) {
    val titleRes = if (invalid) R.string.scan_invalid_title else R.string.scan_title
    val stateRes = if (invalid) R.string.scan_invalid_state else R.string.scan_state
    Text(text = stringResource(titleRes), style = TandemType.titleEmphasis, color = TandemColors.inkOnDark)
    Text(
        text = stringResource(stateRes),
        style = TandemType.titleState,
        color = if (invalid) TandemColors.alert else TandemColors.inkOnDark.copy(alpha = 0.7f),
    )
    Viewfinder(invalid = invalid, frameSource = frameSource, onFrame = onFrame)
    Spacer(Modifier.weight(1f))
    Text(
        text = stringResource(if (invalid) R.string.scan_invalid_hint else R.string.scan_decoded_on_phone),
        style = TandemType.meta,
        color = TandemColors.inkOnDark.copy(alpha = 0.7f),
        modifier = Modifier.fillMaxWidth().padding(bottom = TandemSpacing.md),
    )
    OutlinedButton(
        onClick = if (invalid) onScanAgain else onCancel,
        modifier = Modifier.fillMaxWidth(),
        shape = TandemShapes.button,
        border = BorderStroke(1.dp, TandemColors.inkOnDark.copy(alpha = 0.3f)),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = TandemColors.inkOnDark),
    ) {
        Text(
            text = stringResource(if (invalid) R.string.scan_again else R.string.scan_cancel),
            style = TandemType.rowTitle,
        )
    }
    PairWithoutCameraButton(onPairWithoutCamera)
}

@Composable
private fun Viewfinder(
    invalid: Boolean,
    frameSource: @Composable ((onResult: (ScanResult) -> Unit) -> Unit),
    onFrame: (ScanResult) -> Unit,
) {
    Box(
        modifier =
            Modifier
                .padding(top = TandemSpacing.xxl)
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(TandemRadii.dialog))
                .border(
                    border = BorderStroke(2.dp, if (invalid) TandemColors.alert else TandemColors.inkOnDark),
                    shape = RoundedCornerShape(TandemRadii.dialog),
                ),
    ) {
        frameSource(onFrame)
    }
}

/** Secondary entry to manual pairing (E73-03, ADR-008); never replaces or weakens QR pairing. */
@Composable
private fun PairWithoutCameraButton(onPairWithoutCamera: (() -> Unit)?) {
    if (onPairWithoutCamera == null) return
    TextButton(
        onClick = onPairWithoutCamera,
        modifier = Modifier.fillMaxWidth().padding(top = TandemSpacing.sm),
        colors = ButtonDefaults.textButtonColors(contentColor = TandemColors.inkOnDark),
    ) {
        Text(text = stringResource(R.string.scan_pair_without_camera), style = TandemType.rowTitle)
    }
}
