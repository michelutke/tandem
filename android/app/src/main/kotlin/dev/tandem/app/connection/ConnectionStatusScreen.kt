package dev.tandem.app.connection

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import dev.tandem.core.protocol.connection.ConnectionState

/**
 * Displays connection status with fail-closed error messages (E12-16, invariant 5).
 */
@Composable
fun ConnectionStatusScreen(
    state: ConnectionState,
    modifier: Modifier = Modifier,
) {
    val viewModel = ConnectionStatusViewModel()
    val statusText = viewModel.getStatusText(state)

    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = statusText)
    }
}
