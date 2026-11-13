package dev.tandem.app.mirror

import android.content.Intent
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.feature.mirror.MirrorPromptActionDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment

// Invariant 8: this screen never starts capture itself; Start mirroring only leaves through the callback.
@RunWith(AndroidJUnit4::class)
class MirrorRequestScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun mirrorRequestScreen_shown_namesTheMacAndListsThreeFacts() {
        composeRule.setContent { MirrorRequestScreen("MacBook Pro", {}, {}, remoteInputAvailable = true) }

        composeRule.onNodeWithText("Mirror.").assertExists()
        composeRule.onNodeWithText("MacBook Pro wants to see your screen.").assertExists()
        composeRule.onNodeWithText("01").assertExists()
        composeRule.onNodeWithText("Ends when you tap Stop or lock the phone").assertExists()
    }

    @Test
    fun mirrorRequestScreen_remoteInputAvailable_claimsTapAndType() {
        composeRule.setContent { MirrorRequestScreen("Mac", {}, {}, remoteInputAvailable = true) }

        composeRule.onNodeWithText("Mac can tap and type while this is on").assertExists()
    }

    @Test
    fun mirrorRequestScreen_remoteInputUnavailable_doesNotClaimTapAndTypeAndShowsViewOnlyWording() {
        composeRule.setContent { MirrorRequestScreen("Mac", {}, {}, remoteInputAvailable = false) }

        composeRule.onNodeWithText("Mac can tap and type while this is on").assertDoesNotExist()
        composeRule
            .onNodeWithText("To let your Mac tap and type, allow Tandem in Accessibility settings.")
            .assertExists()
    }

    @Test
    fun mirrorRequestScreen_startAndNotNow_invokeOnlyTheirOwnCallbacks() {
        var started = 0
        var declined = 0
        composeRule.setContent {
            MirrorRequestScreen("Mac", { started++ }, { declined++ }, remoteInputAvailable = true)
        }

        composeRule.onNodeWithText("Not now").performClick()
        assertEquals(0, started)
        assertEquals(1, declined)
        composeRule.onNodeWithText("Start mirroring").performClick()
        assertEquals(1, started)
    }

    @Test
    fun mirrorRequestActivity_noLivePromptController_finishesImmediately() {
        MirrorPromptActionDispatcher.controller = null

        val activity =
            Robolectric
                .buildActivity(
                    MirrorRequestActivity::class.java,
                    Intent(RuntimeEnvironment.getApplication(), MirrorRequestActivity::class.java),
                ).create()
                .get()

        assertTrue(activity.isFinishing)
    }
}
