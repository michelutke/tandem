package dev.tandem.core.designsystem.components

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E00-31 acceptance: "DotRing/DotChart expose a TalkBack content description with the numeric
// value". Compose `ui:` test under Robolectric (tandem.android.robolectric convention).
@RunWith(AndroidJUnit4::class)
class DotRingTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun dotRing_value43_contentDescriptionReads43Percent() {
        composeRule.setContent {
            DotRing(value = 43, maxValue = 100, unit = "%")
        }

        composeRule.onNodeWithContentDescription("43%").assertExists()
    }
}
