package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

class ConnectionStatusViewModelTest {
    @Test
    fun connectionStatusViewModel_failedState_neverRendersConnectingOrBlank() {
        val failedState = ConnectionState.Failed(ConnectionFailure.Timeout)
        val viewModel = ConnectionStatusViewModel()

        val renderedText = viewModel.getStatusText(failedState)

        assertFalse(renderedText.contains("Connecting", ignoreCase = true))
        assertFalse(renderedText.isBlank())
    }
}
