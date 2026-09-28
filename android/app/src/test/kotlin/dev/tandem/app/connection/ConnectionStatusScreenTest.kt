package dev.tandem.app.connection

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant

// E20-09 tdd:
//   ui: connectionStatusScreen_eachState_rendersExactLabel
//   ui: connectionStatusScreen_isolationHintState_rendersExactHintText
@RunWith(AndroidJUnit4::class)
class ConnectionStatusScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val macName = "Michel's MacBook Pro"

    private fun statusTextFor(
        state: ConnectionState,
        unreachableCycles: Int = 0,
    ): String {
        val viewModel =
            ConnectionStatusViewModel(
                connectionState = MutableStateFlow(state),
                failedCycles = MutableStateFlow(unreachableCycles),
                macName = MutableStateFlow(macName),
            )
        return runBlocking { viewModel.statusText.first() }
    }

    @Test
    fun connectionStatusScreen_eachState_rendersExactLabel() {
        val cases =
            listOf(
                statusTextFor(ConnectionState.Ready(Instant.EPOCH)) to "Connected to $macName",
                statusTextFor(ConnectionState.Connecting) to "Connecting…",
                statusTextFor(ConnectionState.Connecting, unreachableCycles = 1) to "Reconnecting…",
                statusTextFor(ConnectionState.Disconnected()) to "Disconnected",
                statusTextFor(
                    ConnectionState.Failed(ConnectionFailure.HandshakeError("PIN_MISMATCH")),
                ) to "Error: The PIN doesn't match. This device is not trusted.",
            )

        cases.forEach { (renderedText, expectedLabel) ->
            assert(renderedText == expectedLabel) { "expected \"$expectedLabel\", got \"$renderedText\"" }
        }

        var statusText by mutableStateOf(cases.first().first)
        composeRule.setContent {
            ConnectionStatusScreen(statusText = statusText)
        }

        cases.forEach { (renderedText, expectedLabel) ->
            statusText = renderedText
            composeRule.waitForIdle()
            composeRule.onNodeWithText(expectedLabel).assertExists()
        }
    }

    @Test
    fun connectionStatusScreen_isolationHintState_rendersExactHintText() {
        val hint =
            "Can't reach your Mac. Make sure both devices are on the same Wi-Fi. Guest networks " +
                "and hotspots often block devices from reaching each other."

        val renderedText = statusTextFor(ConnectionState.Disconnected(), unreachableCycles = 3)
        assert(renderedText == hint) { "expected \"$hint\", got \"$renderedText\"" }

        composeRule.setContent {
            ConnectionStatusScreen(statusText = renderedText)
        }

        composeRule.onNodeWithText(hint).assertExists()
    }
}
