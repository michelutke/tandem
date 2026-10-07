package dev.tandem.app.home

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E20-17 tdd:
//   ui: homeRing_idle_showsSyncedTodayCount
//   ui: homeRing_transferRunning_showsTransferPercent
//   ui: homeRing_reconnecting_showsCountdownAndGreyDots
@RunWith(AndroidJUnit4::class)
class HomeScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    // DotRing's Box clears and re-sets its own semantics (a single "$value$unit" content
    // description), so its numeral/label Text nodes are only present in the unmerged tree.
    private fun ringNodeWithText(text: String) = composeRule.onNodeWithText(text, useUnmergedTree = true)

    @Test
    fun homeRing_idle_showsSyncedTodayCount() {
        composeRule.setContent {
            HomeScreen(
                statusLine = "Linked to MacBook Pro.",
                ringState = HomeRingState.Idle(itemsSyncedToday = 7, sevenDayAverage = 10),
            )
        }

        ringNodeWithText("7").assertExists()
        ringNodeWithText("synced today").assertExists()
    }

    @Test
    fun homeRing_transferRunning_showsTransferPercent() {
        var ringState by mutableStateOf<HomeRingState>(HomeRingState.Idle(itemsSyncedToday = 7, sevenDayAverage = 10))
        composeRule.setContent {
            HomeScreen(
                statusLine = "Linked to MacBook Pro.",
                ringState = ringState,
            )
        }
        ringNodeWithText("7").assertExists()

        ringState = HomeRingState.Transfer(percent = 43, fileName = "photo.png", toMac = true)
        composeRule.waitForIdle()

        ringNodeWithText("43").assertExists()
        ringNodeWithText("photo.png → Mac").assertExists()

        ringState = HomeRingState.Idle(itemsSyncedToday = 8, sevenDayAverage = 10)
        composeRule.waitForIdle()

        ringNodeWithText("8").assertExists()
        ringNodeWithText("synced today").assertExists()
    }

    @Test
    fun homeRing_reconnecting_showsCountdownAndGreyDots() {
        val reconnecting = HomeRingState.Reconnecting(secondsToNextAttempt = 5, attemptNumber = 2)

        // "Grey dots" is DotRing's all-unlit rendering, which it only draws when the ring's
        // fraction is 0 (drawRingDots's `litDots <= 0` branch) -- asserted here directly against
        // the mapping this state feeds it, since Canvas-drawn dots have no semantics tree to query.
        assertEquals(0, reconnecting.toDotRingContent().maxValue)

        composeRule.setContent {
            HomeScreen(
                statusLine = "Reconnecting…",
                ringState = reconnecting,
            )
        }

        ringNodeWithText("5").assertExists()
        ringNodeWithText("next try · attempt 2").assertExists()
    }
}
