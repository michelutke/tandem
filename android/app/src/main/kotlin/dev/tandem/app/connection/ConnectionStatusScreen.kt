package dev.tandem.app.connection

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

/**
 * Displays [statusText] -- [ConnectionStatusViewModel]'s rendering of the connection state,
 * reconnect-backoff cycle count and paired Mac name (E20-09, invariant 5).
 */
@Composable
fun ConnectionStatusScreen(
    statusText: String,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = statusText)
    }
}
