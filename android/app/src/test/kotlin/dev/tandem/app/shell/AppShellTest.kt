package dev.tandem.app.shell

import android.net.Uri
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.app.connection.PairingAddressStore
import dev.tandem.app.home.HomeRingState
import dev.tandem.app.onboarding.FakePermissionChecker
import dev.tandem.app.onboarding.OnboardingViewModel
import dev.tandem.app.onboarding.RecordingPermissionRequester
import dev.tandem.app.onboarding.WELCOME_STATE
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.trust.PeerRecord
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import java.io.File
import java.util.Base64

// E20-25 tdd:
//   ui: mainActivity_freshInstall_showsOnboarding
//   ui: mainActivity_paired_showsHomeAndSettingsUnpairReturnsToOnboarding
@RunWith(AndroidJUnit4::class)
class AppShellTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private val peers = MutableStateFlow<List<PeerRecord>>(emptyList())
    private var batteryRestricted = false
    private var connected = true
    private var sendCount = 0
    private val unpaired = mutableListOf<SpkiFingerprint>()

    private fun setShell() {
        val dependencies =
            AppShellDependencies(
                peers = peers,
                statusLine = flowOf("Linked to MacBook Pro."),
                ringState = MutableStateFlow(HomeRingState.Idle(itemsSyncedToday = 0, sevenDayAverage = 0)),
                onboarding =
                    OnboardingViewModel(RecordingPermissionRequester(), FakePermissionChecker()),
                isBatteryRestricted = { batteryRestricted },
                addressStore = PairingAddressStore(File.createTempFile("addr", null)),
                pairingStarter = PairingStarter {},
                unpair = { fingerprint ->
                    unpaired += fingerprint
                    peers.value = emptyList()
                },
                onSendClipboard = { sendCount++ },
                isConnected = { connected },
            )
        composeRule.setContent { AppShell(navigator = AppShellNavigator(peers), dependencies = dependencies) }
    }

    @Test
    fun mainActivity_freshInstall_showsOnboarding() {
        setShell()

        composeRule.onNodeWithText(WELCOME_STATE).assertExists()
        composeRule.onNodeWithText("Home").assertDoesNotExist()
    }

    @Test
    fun mainActivity_paired_showsHomeAndSettingsUnpairReturnsToOnboarding() {
        peers.value = listOf(PEER)
        setShell()

        composeRule.onNodeWithText("Linked to MacBook Pro.").assertExists()

        composeRule.onNodeWithText("Settings").performClick()
        composeRule.onNodeWithText("Unpair").performClick()
        composeRule.onAllNodesWithText("Unpair").onLast().performClick()
        composeRule.waitForIdle()

        assertEquals(1, unpaired.size)
        composeRule.onNodeWithText(WELCOME_STATE).assertExists()
    }

    @Test
    fun settings_batteryUnrestrictedThenResume_updatesBatteryRow() {
        batteryRestricted = true
        peers.value = listOf(PEER)
        setShell()
        composeRule.onNodeWithText("Settings").performClick()
        composeRule.onNodeWithText("Restricted").assertExists()

        batteryRestricted = false
        composeRule.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        composeRule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)

        composeRule.onNodeWithText("Unrestricted").assertExists()
    }

    @Test
    fun settings_fixTapped_launchesDirectBatteryExemptionDialog() {
        batteryRestricted = true
        peers.value = listOf(PEER)
        setShell()
        composeRule.onNodeWithText("Settings").performClick()

        composeRule.onNodeWithText("Fix").performClick()

        val startedIntent = shadowOf(composeRule.activity).nextStartedActivity
        assertEquals(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, startedIntent?.action)
        assertEquals(Uri.parse("package:${composeRule.activity.packageName}"), startedIntent?.data)
    }

    @Test
    fun home_notificationsAndActivityTapped_showEachScreen() {
        peers.value = listOf(PEER)
        setShell()

        composeRule.onAllNodesWithText("Notifications").onLast().performClick()
        composeRule.onNodeWithText("Notifications.").assertExists()
        composeRule.onNodeWithText("Activity").performClick()
        composeRule.onNodeWithText("Activity.").assertExists()
    }

    @Test
    fun home_sendClipboardWhileDisconnected_showsNotConnectedSnackbar() {
        connected = false
        peers.value = listOf(PEER)
        setShell()

        composeRule.onNodeWithText("↑").performClick()
        composeRule.onNodeWithText("Send clipboard to Mac").performClick()

        composeRule.onNodeWithText("Not connected to your Mac.").assertExists()
        assertEquals(0, sendCount)
    }

    @Test
    fun home_sendClipboardWhileConnected_sendsWithoutSnackbar() {
        peers.value = listOf(PEER)
        setShell()

        composeRule.onNodeWithText("↑").performClick()
        composeRule.onNodeWithText("Send clipboard to Mac").performClick()

        composeRule.onNodeWithText("Not connected to your Mac.").assertDoesNotExist()
        assertEquals(1, sendCount)
    }

    private companion object {
        val FINGERPRINT_BYTES = ByteArray(32) { it.toByte() }
        val PEER =
            PeerRecord(
                deviceId = "mac-1",
                displayName = "MacBook Pro",
                spkiSha256Base64Url = Base64.getUrlEncoder().withoutPadding().encodeToString(FINGERPRINT_BYTES),
                pairedAtEpochMs = 0L,
                lastSeenEpochMs = 0L,
                capabilities = emptyList(),
            )
    }
}
