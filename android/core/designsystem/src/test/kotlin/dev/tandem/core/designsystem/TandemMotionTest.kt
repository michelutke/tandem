package dev.tandem.core.designsystem

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E00-31 acceptance: "With 'Remove animations' on, springs are replaced by instant state
// changes". Compose `ui:` test under Robolectric (tandem.android.robolectric convention): records
// every value `tandemAnimateFloatAsState` emits while the test clock auto-advances to settle, so
// a `snap()` (one step, straight to the target) is distinguishable from a spring (many
// intermediate values as it eases in).
@RunWith(AndroidJUnit4::class)
class TandemMotionTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun motion_removeAnimationsEnabled_noSpringAnimation() {
        var target by mutableFloatStateOf(0f)
        val recordedValues = mutableListOf<Float>()

        composeRule.setContent {
            val animated by tandemAnimateFloatAsState(
                targetValue = target,
                spec = spring(stiffness = Spring.StiffnessVeryLow),
                reduceMotion = true,
            )
            recordedValues.add(animated)
        }
        composeRule.waitForIdle()

        target = 100f
        composeRule.waitForIdle()

        assertEquals(100f, recordedValues.last(), 0.01f)
        assertEquals(listOf(0f, 100f), recordedValues.distinct())
    }

    @Test
    fun motion_removeAnimationsDisabled_springAnimatesGradually() {
        var target by mutableFloatStateOf(0f)
        val recordedValues = mutableListOf<Float>()

        composeRule.setContent {
            val animated by tandemAnimateFloatAsState(
                targetValue = target,
                spec = spring(stiffness = Spring.StiffnessVeryLow),
                reduceMotion = false,
            )
            recordedValues.add(animated)
        }
        composeRule.waitForIdle()

        target = 100f
        composeRule.waitForIdle()

        assertEquals(100f, recordedValues.last(), 0.01f)
        assertTrue(
            "expected the spring to pass through several intermediate values, got ${recordedValues.distinct()}",
            recordedValues.distinct().size > 10,
        )
    }
}
