package dev.tandem.app.onboarding

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
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

        composeRule.onNodeWithText(WELCOME_STATE).assertExists()
        composeRule.onNodeWithText(BATTERY_ONBOARDING_TITLE).assertDoesNotExist()
        composeRule.onNodeWithText(PERMISSIONS_TITLE).assertDoesNotExist()
    }

    @Test
    fun onboarding_getStartedThenSkip_showsPermissionsThenScan() {
        setOnboarding()

        composeRule.onNodeWithText(WELCOME_GET_STARTED_LABEL).performClick()
        composeRule.onNodeWithText(PERMISSIONS_TITLE).assertExists()
        composeRule.onNodeWithText(ONBOARDING_SCAN_TITLE).assertDoesNotExist()

        composeRule.onNodeWithText(PERMISSIONS_SKIP_LABEL).performClick()
        composeRule.onNodeWithText(ONBOARDING_SCAN_TITLE).assertExists()
    }

    @Test
    fun permissionsScreen_rowTapped_requestsThatPermissionAndDenialKeepsRowOff() {
        setOnboarding()
        composeRule.onNodeWithText(WELCOME_GET_STARTED_LABEL).performClick()

        composeRule.onNodeWithText(PermissionRow.CAMERA.label).performClick()

        assertEquals(listOf(OnboardingPermission.CAMERA), requester.requested)
        composeRule.onNodeWithText(PermissionRow.CAMERA.reason).assertExists()
        composeRule.onNodeWithText(PERMISSION_ON_LABEL).assertDoesNotExist()
        composeRule.onNodeWithText(PERMISSIONS_SKIP_LABEL).assertExists()
    }

    @Test
    fun permissionsScreen_everythingGranted_showsContinue() {
        checker.granted += OnboardingPermission.entries
        setOnboarding()
        composeRule.onNodeWithText(WELCOME_GET_STARTED_LABEL).performClick()

        composeRule.onNodeWithText(PERMISSIONS_CONTINUE_LABEL).assertExists()
        composeRule.onNodeWithText(PERMISSIONS_SKIP_LABEL).assertDoesNotExist()
    }

    @Test
    fun permissionsScreen_batteryGrantedInSettingsThenResume_rowShowsOn() {
        setOnboarding()
        composeRule.onNodeWithText(WELCOME_GET_STARTED_LABEL).performClick()
        composeRule.onNodeWithText(PERMISSION_ON_LABEL).assertDoesNotExist()

        checker.granted += OnboardingPermission.BATTERY
        composeRule.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        composeRule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)

        composeRule.onNodeWithText(PERMISSION_ON_LABEL).assertExists()
    }
}
