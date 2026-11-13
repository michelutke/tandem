package dev.tandem.app.incoming

import android.content.Intent
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.feature.files.NotificationTransferPrompter
import dev.tandem.feature.files.TransferActionDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment

@RunWith(AndroidJUnit4::class)
class IncomingFileSheetTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun incomingFileSheet_shown_namesFileSizeAndFolderWithBothActions() {
        composeRule.setContent { IncomingFileSheet("scan-0924.pdf", "1.8 MB", {}, {}, {}) }

        composeRule.onNodeWithText("From Mac.").assertExists()
        composeRule.onNodeWithText("scan-0924.pdf · 1.8 MB").assertExists()
        composeRule.onNodeWithText("Save to").assertExists()
        composeRule.onNodeWithText("Download/Tandem").assertExists()
    }

    @Test
    fun incomingFileSheet_acceptAndDecline_invokeTheirCallbacks() {
        var accepted = 0
        var declined = 0
        composeRule.setContent { IncomingFileSheet("a.pdf", "1 kB", { accepted++ }, { declined++ }, {}) }

        composeRule.onNodeWithText("Accept").performClick()
        composeRule.onNodeWithText("Decline").performClick()

        assertEquals(1, accepted)
        assertEquals(1, declined)
    }

    @Test
    fun incomingFileActivity_noLiveAcceptFlow_finishesImmediately() {
        TransferActionDispatcher.acceptFlow = null
        val intent =
            Intent(RuntimeEnvironment.getApplication(), IncomingFileActivity::class.java)
                .putExtra(NotificationTransferPrompter.EXTRA_OFFER_ID, "offer")
                .putExtra(NotificationTransferPrompter.EXTRA_DISPLAY_NAME, "a.pdf")

        val activity = Robolectric.buildActivity(IncomingFileActivity::class.java, intent).create().get()

        assertTrue(activity.isFinishing)
    }
}
