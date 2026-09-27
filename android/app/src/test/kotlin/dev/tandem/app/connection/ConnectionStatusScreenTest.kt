package dev.tandem.app.connection

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ConnectionStatusScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun connectionStatusScreen_failedVersionMismatch_showsVersionMismatchText() {
        val versionMismatchState =
            ConnectionState.Failed(
                ConnectionFailure.HandshakeError("VERSION_MISMATCH"),
            )

        composeRule.setContent {
            ConnectionStatusScreen(state = versionMismatchState)
        }

        composeRule.onNodeWithText("Version mismatch. Check for app updates.").assertExists()
    }
}
