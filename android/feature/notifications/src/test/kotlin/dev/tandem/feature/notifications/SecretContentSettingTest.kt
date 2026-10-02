package dev.tandem.feature.notifications

import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E30-11 tdd: ui: secretVisibilitySetting_freshInstall_toggleOffWithExactLabel
@RunWith(AndroidJUnit4::class)
class SecretContentSettingTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun secretVisibilitySetting_freshInstall_toggleOffWithExactLabel() {
        val toggles = mutableListOf<Boolean>()

        composeRule.setContent {
            SecretContentSetting(
                checked = SecretNotificationPolicy.SHOW_CONTENT_KEY.default,
                onCheckedChange = { toggles += it },
            )
        }

        composeRule.onNodeWithText("Show content of secret notifications on Mac").assertExists()
        composeRule.onNodeWithTag("switch_secret_content").assertIsOff()
        composeRule.onNodeWithTag("switch_secret_content").performClick()
        assertEquals(listOf(true), toggles)
    }

    @Test
    fun secretVisibilitySetting_checked_toggleOn() {
        composeRule.setContent { SecretContentSetting(checked = true, onCheckedChange = {}) }

        composeRule.onNodeWithTag("switch_secret_content").assertIsOn()
    }
}
