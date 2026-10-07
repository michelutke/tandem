@file:Suppress("MatchingDeclarationName") // AppShell is the file's composable; its dependencies class leads

package dev.tandem.app.shell

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.tandem.app.activity.ActivityEntry
import dev.tandem.app.activity.ActivityScreen
import dev.tandem.app.connection.PairingAddressStore
import dev.tandem.app.di.AppClock
import dev.tandem.app.di.AppDispatchers
import dev.tandem.app.home.HomeRingState
import dev.tandem.app.home.HomeScreen
import dev.tandem.app.onboarding.OnboardingScreen
import dev.tandem.app.onboarding.OnboardingViewModel
import dev.tandem.app.onboarding.launchBatteryExemption
import dev.tandem.app.onboarding.rememberResumeCount
import dev.tandem.app.settings.AppPermissionGateway
import dev.tandem.app.settings.NoAppPermissions
import dev.tandem.app.settings.PermissionsSettingsScreen
import dev.tandem.app.settings.RotationSettingsScreen
import dev.tandem.app.settings.RotationSettingsViewModel
import dev.tandem.app.settings.SettingsScreen
import dev.tandem.app.settings.SettingsState
import dev.tandem.app.settings.SyncFeature
import dev.tandem.app.settings.keyShortCode
import dev.tandem.app.settings.statuses
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.components.FloatingToolbarItem
import dev.tandem.core.designsystem.components.TandemBottomBar
import dev.tandem.core.designsystem.components.TandemLoadingIndicator
import dev.tandem.core.designsystem.components.TandemScaffold
import dev.tandem.core.designsystem.rememberScreenTransition
import dev.tandem.core.pairing.PairingState
import dev.tandem.core.storage.trust.PeerRecord
import dev.tandem.feature.notifications.PerAppFilterRow
import dev.tandem.feature.notifications.PerAppNotificationFilterScreen
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Clock
import java.time.LocalDate
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
    val onSendFiles: () -> Unit = {},
    val rotation: RotationSettingsViewModel? = null,
    val permissions: AppPermissionGateway = NoAppPermissions,
    val isConnected: () -> Boolean = { true },
    val activityEntries: Flow<List<ActivityEntry>> = flowOf(emptyList()),
    val notificationRows: () -> List<PerAppFilterRow> = { emptyList() },
    val onToggleNotificationApp: suspend (packageName: String, allowed: Boolean) -> Unit = { _, _ -> },
    val featureStates: StateFlow<Map<SyncFeature, Boolean>> = ALL_FEATURES_ON,
    val onToggleFeature: suspend (SyncFeature, Boolean) -> Unit = { _, _ -> },
    val clock: Clock = AppClock.system,
)

private val ALL_FEATURES_ON = MutableStateFlow(SyncFeature.entries.associateWith { true })
private val SNACKBAR_BOTTOM_PADDING = 96.dp

/**
 * The app shell (E20-25, F-4.1): onboarding (ending in the pairing scan) until a peer is paired,
 * then Home, Notifications, Activity and Settings behind one shared floating toolbar. Pairing
 * completion is never decided here; see [PairingStarter].
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
    val scope = rememberCoroutineScope()
    val peer = peers.firstOrNull()

    LaunchedEffect(route, pairingState) {
        if (route == ShellRoute.Home && pairingState == PairingState.Paired) dependencies.pairing.reset()
    }

    val snackbarHostState = remember { SnackbarHostState() }

    Box(modifier = Modifier.fillMaxSize()) {
        val currentRoute = route
        when (currentRoute) {
            ShellRoute.Onboarding -> {
                OnboardingOrPairing(pairingState, dependencies, insetsModifier)
            }

            null -> {
                LoadingScreen(insetsModifier)
            }

            else -> {
                TopLevelShell(
                    route = currentRoute,
                    navigator = navigator,
                    dependencies = dependencies,
                    statusLine = statusLine,
                    ringState = ringState,
                    snackbarHostState = snackbarHostState,
                    peer = peer,
                )
            }
        }
        SnackbarHost(
            hostState = snackbarHostState,
            modifier =
                Modifier
                    .align(
                        Alignment.BottomCenter,
                    ).safeDrawingPadding()
                    .padding(bottom = SNACKBAR_BOTTOM_PADDING),
        )
    }
}

/**
 * Home, Notifications, Activity and Settings behind one shared [TandemBottomBar], so the bar never
 * moves between screens; switching screens fades through.
 */
@Composable
@Suppress("LongParameterList") // shell state the top-level routes read
private fun TopLevelShell(
    route: ShellRoute,
    peer: PeerRecord?,
    navigator: AppShellNavigator,
    dependencies: AppShellDependencies,
    statusLine: String,
    ringState: HomeRingState,
    snackbarHostState: SnackbarHostState,
) {
    var showSendSheet by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val transition = rememberScreenTransition()
    Scaffold(
        containerColor = TandemColors.paper,
        bottomBar = {
            TandemBottomBar(
                selected = route.toolbarItem() ?: FloatingToolbarItem.Home,
                onSelect = navigator::select,
                onSend = { showSendSheet = true },
            )
        },
    ) { innerPadding ->
        AnimatedContent(
            targetState = route,
            transitionSpec = { transition },
            modifier = Modifier.padding(innerPadding).consumeWindowInsets(innerPadding),
            label = "TopLevelScreen",
        ) { target ->
            when {
                target == ShellRoute.Home -> {
                    HomeTab(dependencies, statusLine, ringState, Modifier)
                }

                target == ShellRoute.Notifications -> {
                    NotificationsTab(dependencies, Modifier)
                }

                target == ShellRoute.Activity -> {
                    ActivityTab(dependencies, Modifier)
                }

                peer != null -> {
                    SettingsTab(peer, navigator, dependencies, Modifier)
                }

                else -> {
                    LoadingScreen(Modifier)
                }
            }
        }
    }
    if (showSendSheet) {
        ShellSendSheet(dependencies, snackbarHostState, scope) { showSendSheet = false }
    }
}

@Composable
private fun LoadingScreen(modifier: Modifier) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) { TandemLoadingIndicator() }
}

@Composable
private fun SettingsTab(
    peer: PeerRecord,
    navigator: AppShellNavigator,
    dependencies: AppShellDependencies,
    modifier: Modifier,
) {
    val resumeCount by rememberResumeCount()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var showPermissions by rememberSaveable { mutableStateOf(false) }
    if (showPermissions) {
        BackHandler { showPermissions = false }
        PermissionsSettingsScreen(
            statuses = resumeCount.let { dependencies.permissions.statuses() },
            onSelect = dependencies.permissions::request,
            modifier = modifier,
        )
        return
    }
    SettingsScreen(
        state =
            peer.toSettingsState(
                batteryRestricted = resumeCount.let { dependencies.isBatteryRestricted() },
                connected = dependencies.isConnected(),
            ),
        onFixBattery = { launchBatteryExemption(context) },
        onOpenPermissions = { showPermissions = true },
        onRotateKey = {},
        keySection = dependencies.rotation?.let { rotation -> { RotationSection(rotation) } },
        onUnpair = {
            scope.launch {
                dependencies.unpair(peer.fingerprint())
                navigator.resetToHome()
            }
        },
        modifier = modifier,
    )
}

@Composable
private fun ActivityTab(
    dependencies: AppShellDependencies,
    modifier: Modifier,
) {
    val entries by dependencies.activityEntries.collectAsState(initial = emptyList())
    ActivityScreen(
        entries = entries,
        today = LocalDate.now(dependencies.clock),
        modifier = modifier,
    )
}

@Composable
private fun NotificationsTab(
    dependencies: AppShellDependencies,
    modifier: Modifier,
) {
    var rows by remember { mutableStateOf<List<PerAppFilterRow>?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { rows = withContext(AppDispatchers.io) { dependencies.notificationRows() } }
    val loaded = rows.orEmpty()
    TandemScaffold(
        title = "Notifications.",
        state = if (rows == null) "Loading apps." else "${loaded.count { it.allowed }} of ${loaded.size} apps.",
        modifier = modifier,
    ) { padding ->
        if (rows == null) {
            Box(modifier = Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                TandemLoadingIndicator()
            }
        } else {
            PerAppNotificationFilterScreen(
                rows = loaded,
                onToggle = { packageName, allowed ->
                    rows = loaded.map { if (it.packageName == packageName) it.copy(allowed = allowed) else it }
                    scope.launch { dependencies.onToggleNotificationApp(packageName, allowed) }
                },
                modifier = Modifier.padding(padding),
            )
        }
    }
}

private fun PeerRecord.fingerprint(): SpkiFingerprint =
    SpkiFingerprint(Base64.getUrlDecoder().decode(spkiSha256Base64Url))

private fun PeerRecord.toSettingsState(
    batteryRestricted: Boolean,
    connected: Boolean,
) = SettingsState(
    macName = displayName,
    batteryRestricted = batteryRestricted,
    keyShortCode = keyShortCode(spkiSha256Base64Url),
    connected = connected,
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
