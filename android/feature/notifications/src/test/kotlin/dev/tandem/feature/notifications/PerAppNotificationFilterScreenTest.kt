package dev.tandem.feature.notifications

import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E30-04 tdd: ui: perAppFilterScreen_threeInstalledApps_rendersThreeRowsWithToggleState
// Compose `ui:` test under Robolectric (E00-20).
@RunWith(AndroidJUnit4::class)
class PerAppNotificationFilterScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun perAppFilterScreen_threeInstalledApps_rendersThreeRowsWithToggleState() {
        val rows =
            listOf(
                PerAppFilterRow("com.example.chat", "Chat", allowed = true),
                PerAppFilterRow("com.example.social", "Social", allowed = false),
                PerAppFilterRow("com.android.systemui", "System UI", allowed = false),
            )

        composeRule.setContent {
            PerAppNotificationFilterScreen(rows = rows, onToggle = { _, _ -> })
        }

        composeRule.onNodeWithText("Chat").assertExists()
        composeRule.onNodeWithText("Social").assertExists()
        composeRule.onNodeWithText("System UI").assertExists()

        composeRule.onNodeWithTag("switch_com.example.chat").assertIsOn()
        composeRule.onNodeWithTag("switch_com.example.social").assertIsOff()
        composeRule.onNodeWithTag("switch_com.android.systemui").assertIsOff()
    }
}
