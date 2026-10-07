@file:Suppress("MatchingDeclarationName") // AppShell is the file's composable; its dependencies class leads

package dev.tandem.app.shell

import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import dev.tandem.app.connection.PairingAddressStore
import dev.tandem.app.home.HomeRingState
import dev.tandem.app.home.HomeScreen
import dev.tandem.app.onboarding.OnboardingScreen
import dev.tandem.app.onboarding.OnboardingViewModel
import dev.tandem.app.onboarding.rememberResumeCount
import dev.tandem.app.settings.RotationSettingsScreen
import dev.tandem.app.settings.RotationSettingsViewModel
import dev.tandem.app.settings.SettingsScreen
import dev.tandem.app.settings.SettingsState
import dev.tandem.app.settings.keyShortCode
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.designsystem.components.FloatingToolbarItem
import dev.tandem.core.pairing.PairingState
import dev.tandem.core.storage.trust.PeerRecord
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.util.Base64

/** Everything [AppShell] reads or calls; built from the Hilt graph in production, fakes in tests. */
@Suppress("LongParameterList") // one slot per shell collaborator
class AppShellDependencies(
    val peers: Flow<List<PeerRecord>>,
    val statusLine: Flow<String>,
    val ringState: StateFlow<HomeRingState>,
    val onboarding: OnboardingViewModel,
    val isBatteryRestricted: () -> Boolean,
    val addressStore: PairingAddressStore,
    val pairingStarter: PairingStarter,
    val pairing: PairingFlowControls = NoPairingFlowControls,
    val unpair: suspend (SpkiFingerprint) -> Unit,
    val onSendClipboard: () -> Unit,
    val rotation: RotationSettingsViewModel? = null,
    val onOpenPermissionSettings: () -> Unit = {},
)

/**
 * The app shell (E20-25, F-4.1): onboarding (ending in the pairing scan) until a peer is paired,
 * then Home and Settings behind the floating toolbar. Pairing completion is never decided here;
 * see [PairingStarter].
 */
@Composable
fun AppShell(
    navigator: AppShellNavigator,
    dependencies: AppShellDependencies,
    modifier: Modifier = Modifier,
) {
    val insetsModifier = modifier.safeDrawingPadding()
    val route by navigator.route.collectAsState(initial = null)
    val peers by dependencies.peers.collectAsState(initial = emptyList())
    val statusLine by dependencies.statusLine.collectAsState(initial = "")
    val ringState by dependencies.ringState.collectAsState()
    val pairingState by dependencies.pairing.state.collectAsState()
    val resumeCount by rememberResumeCount()
    val scope = rememberCoroutineScope()
    val peer = peers.firstOrNull()

    LaunchedEffect(route, pairingState) {
        if (route == ShellRoute.Home && pairingState == PairingState.Paired) dependencies.pairing.reset()
    }

    when (route) {
        ShellRoute.Onboarding -> {
            OnboardingOrPairing(pairingState, dependencies, insetsModifier)
        }

        ShellRoute.Home -> {
            HomeScreen(
                statusLine = statusLine,
                ringState = ringState,
                selectedToolbarItem = FloatingToolbarItem.Home,
                onToolbarItemSelected = navigator::select,
                onSendClipboard = dependencies.onSendClipboard,
                modifier = insetsModifier,
            )
        }

        ShellRoute.Settings -> {
            if (peer != null) {
                SettingsScreen(
                    state = peer.toSettingsState(resumeCount.let { dependencies.isBatteryRestricted() }),
                    selectedToolbarItem = FloatingToolbarItem.Settings,
                    onToolbarItemSelected = navigator::select,
                    onFixBattery = {},
                    onOpenPermissionSettings = dependencies.onOpenPermissionSettings,
                    onRotateKey = {},
                    keySection = dependencies.rotation?.let { rotation -> { RotationSection(rotation) } },
                    onUnpair = {
                        scope.launch {
                            dependencies.unpair(peer.fingerprint())
                            navigator.resetToHome()
                        }
                    },
                    modifier = insetsModifier,
                )
            }
        }

        null -> {
            Unit
        }
    }
}

private fun PeerRecord.fingerprint(): SpkiFingerprint =
    SpkiFingerprint(Base64.getUrlDecoder().decode(spkiSha256Base64Url))

private fun PeerRecord.toSettingsState(batteryRestricted: Boolean) =
    SettingsState(
        macName = displayName,
        batteryRestricted = batteryRestricted,
        keyShortCode = keyShortCode(spkiSha256Base64Url),
    )

@Composable
private fun OnboardingOrPairing(
    pairingState: PairingState,
    dependencies: AppShellDependencies,
    modifier: Modifier,
) {
    if (pairingState == PairingState.Idle) {
        OnboardingScreen(
            viewModel = dependencies.onboarding,
            onScanAccepted = { onScanAccepted(it, dependencies.addressStore, dependencies.pairingStarter) },
            onCancelScan = {},
            modifier = modifier,
        )
    } else {
        PairingScreen(
            state = pairingState,
            onCodesMatch = dependencies.pairing::confirmCodesMatch,
            onCodesDontMatch = dependencies.pairing::cancel,
            onScanAgain = dependencies.pairing::reset,
            modifier = modifier,
        )
    }
}

@Composable
private fun RotationSection(rotation: RotationSettingsViewModel) {
    val state by rotation.state.collectAsState()
    val fingerprint by rotation.currentFingerprint.collectAsState()
    val actionEnabled by rotation.actionEnabled.collectAsState()
    val disabledReason by rotation.disabledReason.collectAsState()
    RotationSettingsScreen(
        state = state,
        currentFingerprint = fingerprint,
        actionEnabled = actionEnabled,
        disabledReason = disabledReason,
        onRotate = rotation::requestRotation,
        onConfirm = rotation::confirm,
        onCancel = rotation::cancel,
        onDismissResult = rotation::dismissResult,
    )
}
