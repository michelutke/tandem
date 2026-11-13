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
    fun dotRing_value43_contentDescriptionReadsNumeralUnitAndLabelWithSeparator() {
        composeRule.setContent {
            DotRing(numeral = "43", numeralUnit = "%", label = "Sending to Mac", litFraction = 0.43f)
        }

        composeRule.onNodeWithContentDescription("43%, Sending to Mac").assertExists()
    }

    @Test
    fun dotRing_noNumeral_contentDescriptionIsTheLabelOnly() {
        composeRule.setContent {
            DotRing(numeral = "", label = "ringing", pulse = true)
        }

        composeRule.onNodeWithContentDescription("ringing").assertExists()
    }
}
