package dev.tandem.app.onboarding

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.app.R
import dev.tandem.app.appString
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// Onboarding order per ui-spec §7.2: welcome, permissions, scan; denial leaves a row off.
@RunWith(AndroidJUnit4::class)
class OnboardingScreenTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private val requester = RecordingPermissionRequester()
    private val checker = FakePermissionChecker()

    private fun setOnboarding() {
        val viewModel = OnboardingViewModel(requester, checker)
        composeRule.setContent {
            OnboardingScreen(viewModel = viewModel, onScanAccepted = {}, onCancelScan = {})
        }
    }

    @Test
    fun onboarding_fresh_startsWithWelcomeNotBattery() {
        setOnboarding()

        composeRule.onNodeWithText(appString(R.string.welcome_state)).assertExists()
        composeRule.onNodeWithText(BATTERY_ONBOARDING_TITLE).assertDoesNotExist()
        composeRule.onNodeWithText(appString(R.string.permissions_title)).assertDoesNotExist()
    }

    @Test
    fun onboarding_getStartedThenSkip_showsPermissionsThenScan() {
        setOnboarding()

        composeRule.onNodeWithText(appString(R.string.welcome_get_started)).performClick()
        composeRule.onNodeWithText(appString(R.string.permissions_title)).assertExists()
        composeRule.onNodeWithText("Camera needed.").assertDoesNotExist()

        composeRule.onNodeWithText(appString(R.string.permissions_continue)).performClick()
        composeRule.onNodeWithText("Camera needed.").assertExists()
    }

    @Test
    fun permissionsScreen_rowTapped_requestsThatPermissionAndDenialKeepsRowOff() {
        setOnboarding()
        composeRule.onNodeWithText(appString(R.string.welcome_get_started)).performClick()

        composeRule.onAllNodesWithText(appString(R.string.permissions_allow))[CAMERA_ALLOW_INDEX].performClick()

        assertEquals(listOf(OnboardingPermission.CAMERA), requester.requested)
        composeRule.onNodeWithText(appString(PermissionRow.CAMERA.reasonRes)).assertExists()
        composeRule.onNodeWithText(appString(R.string.permissions_granted)).assertDoesNotExist()
        composeRule.onNodeWithText(appString(R.string.permissions_continue)).assertExists()
    }

    @Test
    fun permissionsScreen_everythingGranted_showsContinue() {
        checker.granted += OnboardingPermission.entries
        setOnboarding()
        composeRule.onNodeWithText(appString(R.string.welcome_get_started)).performClick()

        composeRule.onNodeWithText(appString(R.string.permissions_continue)).assertExists()
        composeRule.onNodeWithText(appString(R.string.permissions_allow)).assertDoesNotExist()
    }

    @Test
    fun permissionsScreen_batteryGrantedInSettingsThenResume_rowShowsOn() {
        setOnboarding()
        composeRule.onNodeWithText(appString(R.string.welcome_get_started)).performClick()
        composeRule.onNodeWithText(appString(R.string.permissions_granted)).assertDoesNotExist()

        checker.granted += OnboardingPermission.BATTERY
        composeRule.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        composeRule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)

        composeRule.onNodeWithText(appString(R.string.permissions_granted)).assertExists()
    }

    private companion object {
        const val CAMERA_ALLOW_INDEX = 2
    }
}
