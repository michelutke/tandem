package dev.tandem.app.onboarding

import android.Manifest
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

// E20-14 tdd: ui: scanScreen_rendered_noSkipButtonAndCameraRequestedOnScanTap
@RunWith(AndroidJUnit4::class)
class OnboardingScanScreenTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun scanScreen_rendered_noSkipButtonAndCameraRequestedOnScanTap() {
        composeRule.setContent {
            OnboardingScanScreen(onScanAccepted = {}, onCancel = {})
        }

        composeRule.onNodeWithText(ONBOARDING_SCAN_TITLE).assertExists()
        composeRule.onNodeWithText("Skip").assertDoesNotExist()
        composeRule.onNodeWithText("Grant").assertExists()

        composeRule.onNodeWithText("Grant").performClick()

        val requestedPermission = shadowOf(composeRule.activity).lastRequestedPermission
        assertNotNull("expected the CAMERA permission to have been requested", requestedPermission)
        assertEquals(Manifest.permission.CAMERA, requestedPermission?.requestedPermissions?.firstOrNull())
    }
}
