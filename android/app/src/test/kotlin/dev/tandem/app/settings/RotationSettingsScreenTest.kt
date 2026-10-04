package dev.tandem.app.settings

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E70-06 tdd:
//   ui: rotationSettingsScreen_successState_rendersNewFingerprint
@RunWith(AndroidJUnit4::class)
class RotationSettingsScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun rotationSettingsScreen_successState_rendersNewFingerprint() {
        composeRule.setContent {
            RotationSettingsScreen(
                state = RotationState.Success("E5F6 0718"),
                currentFingerprint = "A1B2 C3D4",
                actionEnabled = true,
                disabledReason = null,
                onRotate = {},
                onConfirm = {},
                onCancel = {},
                onDismissResult = {},
            )
        }

        composeRule.onNodeWithText("E5F6 0718", substring = true).assertIsDisplayed()
    }
}
