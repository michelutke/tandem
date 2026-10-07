package dev.tandem.app

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.widget.Toast
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import dagger.hilt.android.AndroidEntryPoint
import dagger.hilt.android.EntryPointAccessors
import dev.tandem.app.di.AppClock
import dev.tandem.app.di.AppDispatchers
import dev.tandem.app.home.ActivityHomeRingStateSource
import dev.tandem.app.onboarding.OnboardingViewModel
import dev.tandem.app.onboarding.SystemBatteryOptimizationSource
import dev.tandem.app.onboarding.SystemPermissionChecker
import dev.tandem.app.onboarding.SystemPermissionRequester
import dev.tandem.app.service.ServiceStarter
import dev.tandem.app.service.TandemService
import dev.tandem.app.service.TrustStorePairedPeerRepository
import dev.tandem.app.settings.RotationSettingsViewModel
import dev.tandem.app.settings.SystemAppPermissionGateway
import dev.tandem.app.shell.AppShell
import dev.tandem.app.shell.AppShellDependencies
import dev.tandem.app.shell.AppShellNavigator
import dev.tandem.app.shell.ShellEntryPoint
import dev.tandem.core.designsystem.TandemTheme
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.ui.TandemActivity
import dev.tandem.feature.clipboard.AndroidClipboardReader
import dev.tandem.feature.clipboard.ClipboardReader
import dev.tandem.feature.clipboard.ClipboardSender
import dev.tandem.feature.clipboard.LiveClipboardSession
import dev.tandem.feature.files.PickFilesActivity
import dev.tandem.feature.notifications.FilterOverride
import dev.tandem.feature.notifications.SystemInstalledAppsSource
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.security.MessageDigest

// Launcher activity (E00-03). E20-25: hosts the app shell (onboarding until paired, then Home and
// Settings); see [AppShell].
//
// E31-07: also this app's foreground-capture and in-app "Send clipboard to Mac" entry points
// (PRD F-6.2, UC-13); the button lives in Home's send sheet.
//   - Foreground capture: whenever this Activity gains window focus, [onWindowFocusChanged] reads
//     the clipboard via [clipboardReaderProvider] and, if it holds text and is not sensitive,
//     sends it via [ClipboardSender]. The clipboard is read from no other place or callback, so a
//     background Tandem process never attempts a read outside this window
//     (docs/planning/backlog/phase-3.yaml E31-07 acceptance criterion 3).
//   - A sensitive clip (`ClipDescription.EXTRA_IS_SENSITIVE`, API 33+) is silently skipped on
//     window focus, but sent (with `sensitive = true`) when the user explicitly taps the button --
//     the user's explicit action is treated as intentional, unlike the passive focus-gained
//     capture.
//
// [sessionProvider]/[dispatcher]/[clipboardReaderProvider] are `internal var` seams, the same
// no-composition-root convention `ShareTargetActivity`/`ProcessTextActivity` (E31-06) use: nothing
// yet wires a live [TandemSession] into a feature entry point.
@AndroidEntryPoint
class MainActivity : TandemActivity() {
    internal var sessionProvider: (Context) -> TandemSession? = { LiveClipboardSession.current }
    internal var dispatcher: CoroutineDispatcher = AppDispatchers.default
    internal var clipboardReaderProvider: (Context) -> ClipboardReader = { context -> AndroidClipboardReader(context) }

    internal var serviceStarterProvider: (MainActivity) -> ServiceStarter = ::liveServiceStarter

    internal var shellDependenciesProvider: (MainActivity) -> AppShellDependencies = ::liveShellDependencies

    private val requestRuntimePermissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) { serviceStarterProvider(this@MainActivity).keepStarted() }
        }
        val dependencies = shellDependenciesProvider(this)
        setContent {
            val navigator = remember { AppShellNavigator(dependencies.peers) }
            TandemTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AppShell(navigator = navigator, dependencies = dependencies)
                }
            }
        }
    }

    private fun liveServiceStarter(activity: MainActivity): ServiceStarter {
        val app = activity.application as TandemApplication
        return ServiceStarter(
            pairedPeerRepository = TrustStorePairedPeerRepository(app.trustStore),
            startForegroundService = { activity.startForegroundService(Intent(activity, TandemService::class.java)) },
        )
    }

    private fun liveShellDependencies(activity: MainActivity): AppShellDependencies {
        val app = application as TandemApplication
        val graph = EntryPointAccessors.fromApplication(applicationContext, ShellEntryPoint::class.java)
        val pairingFlow = graph.pairingFlow()
        val rotationComposition = graph.rotationComposition()
        return AppShellDependencies(
            peers = graph.trustStore().observeList(),
            statusLine = graph.connectionStatusViewModel().statusText,
            ringState =
                ActivityHomeRingStateSource(
                    app.activityStore.entries,
                    AppClock.system,
                    CoroutineScope(SupervisorJob() + dispatcher),
                ).state,
            onboarding =
                OnboardingViewModel(
                    SystemPermissionRequester(activity) { requestRuntimePermissions.launch(it) },
                    SystemPermissionChecker(activity),
                ),
            isBatteryRestricted = { !SystemBatteryOptimizationSource(activity).isIgnoringBatteryOptimizations() },
            addressStore = graph.pairingAddressStore(),
            pairingStarter = pairingFlow,
            pairing = pairingFlow,
            unpair = { fingerprint ->
                graph.unpairAction().unpair(
                    fingerprint,
                    graph
                        .sessionRegistry()
                        .current.value
                        ?.session,
                )
            },
            onSendClipboard = ::onSendClipboardButtonTapped,
            onSendFiles = ::onSendFilesTapped,
            isConnected = { sessionProvider(this) != null },
            featureStates = app.featureToggles.states,
            onToggleFeature = app.featureToggles::set,
            activityEntries = app.activityStore.entries,
            notificationRows = {
                app.notificationFilter.rowsFor(SystemInstalledAppsSource(this).installedApps())
            },
            onToggleNotificationApp = { packageName, allowed ->
                app.notificationFilter.setOverride(
                    packageName,
                    if (allowed) FilterOverride.ALLOW else FilterOverride.DENY,
                )
            },
            permissions = permissionGateway(activity),
            rotation =
                RotationSettingsViewModel(
                    rotator = rotationComposition.keyRotator,
                    hasAuthenticatedSession = rotationComposition.authenticated,
                    currentFingerprint = rotationComposition.activeFingerprint,
                    scope = CoroutineScope(SupervisorJob() + dispatcher),
                ),
        )
    }

    private fun permissionGateway(activity: MainActivity) =
        SystemAppPermissionGateway(activity, requestRuntimePermissions = { requestRuntimePermissions.launch(it) })

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return

        val clip = clipboardReaderProvider(this).currentClip()
        if (clip != null && !clip.sensitive && shouldSendCaptured(clip.text)) {
            sendClip(clip.text, sensitive = false)
        }
    }

    private fun shouldSendCaptured(text: String): Boolean {
        val contentHash = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
        return LiveClipboardSession.loopGuard.shouldSend(contentHash)
    }

    internal fun onSendClipboardButtonTapped() {
        val clip = clipboardReaderProvider(this).currentClip()
        if (clip == null) {
            showToast(R.string.clipboard_empty)
            return
        }
        sendClip(clip.text, sensitive = clip.sensitive, confirm = true)
    }

    internal fun onSendFilesTapped() {
        startActivity(Intent(this, PickFilesActivity::class.java))
    }

    private fun sendClip(
        text: String,
        sensitive: Boolean,
        confirm: Boolean = false,
    ) {
        val session = sessionProvider(this) ?: return
        CoroutineScope(SupervisorJob() + dispatcher).launch {
            val sent =
                ClipboardSender.send(
                    text,
                    session,
                    sensitive = sensitive,
                    onTooLarge = { if (confirm) showToast(R.string.clipboard_too_large) },
                )
            if (sent && confirm) showToast(R.string.clipboard_sent)
        }
    }

    private fun showToast(
        @StringRes message: Int,
    ) {
        runOnUiThread { Toast.makeText(this, message, Toast.LENGTH_SHORT).show() }
    }
}
