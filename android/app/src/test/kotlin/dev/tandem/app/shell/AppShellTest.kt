package dev.tandem.app.shell

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.app.connection.PairingAddressStore
import dev.tandem.app.home.HomeRingState
import dev.tandem.app.onboarding.BatteryOnboardingViewModel
import dev.tandem.app.onboarding.FakeBatteryOptimizationSource
import dev.tandem.app.onboarding.FakeDeviceManufacturerSource
import dev.tandem.app.onboarding.NOTIFICATION_LISTENER_ONBOARDING_TITLE
import dev.tandem.app.onboarding.OnboardingViewModel
import dev.tandem.app.onboarding.RecordingPermissionRequester
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.trust.PeerRecord
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.Base64

// E20-25 tdd:
//   ui: mainActivity_freshInstall_showsOnboarding
//   ui: mainActivity_paired_showsHomeAndSettingsUnpairReturnsToOnboarding
@RunWith(AndroidJUnit4::class)
class AppShellTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val peers = MutableStateFlow<List<PeerRecord>>(emptyList())
    private val unpaired = mutableListOf<SpkiFingerprint>()

    private fun setShell() {
        val dependencies =
            AppShellDependencies(
                peers = peers,
                statusLine = flowOf("Linked to MacBook Pro."),
                ringState = MutableStateFlow(HomeRingState.Idle(itemsSyncedToday = 0, sevenDayAverage = 0)),
                onboarding =
                    OnboardingViewModel(
                        BatteryOnboardingViewModel(
                            FakeBatteryOptimizationSource(ignoringBatteryOptimizations = true),
                            FakeDeviceManufacturerSource(manufacturer = "Google"),
                        ),
                        RecordingPermissionRequester(),
                    ),
                isBatteryRestricted = { false },
                addressStore = PairingAddressStore(File.createTempFile("addr", null)),
                pairingStarter = PairingStarter {},
                unpair = { fingerprint ->
                    unpaired += fingerprint
                    peers.value = emptyList()
                },
                onSendClipboard = {},
            )
        composeRule.setContent { AppShell(navigator = AppShellNavigator(peers), dependencies = dependencies) }
    }

    @Test
    fun mainActivity_freshInstall_showsOnboarding() {
        setShell()

        composeRule.onNodeWithText(NOTIFICATION_LISTENER_ONBOARDING_TITLE).assertExists()
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
        composeRule.onNodeWithText(NOTIFICATION_LISTENER_ONBOARDING_TITLE).assertExists()
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
