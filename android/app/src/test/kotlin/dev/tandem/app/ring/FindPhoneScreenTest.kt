package dev.tandem.app.ring

import android.content.Intent
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment

@RunWith(AndroidJUnit4::class)
class FindPhoneScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun findPhoneScreen_shown_namesTheMacAndFoundItInvokesCallback() {
        var found = 0
        composeRule.setContent { FindPhoneScreen("MacBook Pro", { found++ }) }

        composeRule.onNodeWithText("Ringing.").assertExists()
        composeRule.onNodeWithText("From MacBook Pro.").assertExists()
        composeRule.onNodeWithText("Found it").performClick()
        assertEquals(1, found)
    }

    @Test
    fun findPhoneActivity_notRinging_finishesImmediately() {
        LiveRingController.mutableRinging.value = false

        val activity =
            Robolectric
                .buildActivity(
                    FindPhoneActivity::class.java,
                    Intent(RuntimeEnvironment.getApplication(), FindPhoneActivity::class.java),
                ).create()
                .get()

        assertTrue(activity.isFinishing)
    }
}
