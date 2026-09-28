package dev.tandem.app.onboarding

import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

// E20-14 tdd: ui: deniedFeatureRow_tapped_launchesMatchingSettingsIntent
@RunWith(AndroidJUnit4::class)
class DisabledFeatureRowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun deniedFeatureRow_tapped_launchesMatchingSettingsIntent() {
        composeRule.setContent {
            DisabledFeatureRow(
                featureName = NOTIFICATION_LISTENER_ONBOARDING_TITLE,
                settingsIntentAction = Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS,
            )
        }

        composeRule.onNodeWithText(NOTIFICATION_LISTENER_ONBOARDING_TITLE).assertExists()
        composeRule.onNodeWithText(DISABLED_FEATURE_ROW_LABEL).assertExists()

        composeRule.onNodeWithText(DISABLED_FEATURE_ROW_LABEL).performClick()

        val startedIntent = shadowOf(composeRule.activity).nextStartedActivity
        assertEquals(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS, startedIntent?.action)
    }
}
