package dev.tandem.app.shell

import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import dev.tandem.app.home.HomeRingState
import dev.tandem.app.home.HomeScreen
import dev.tandem.app.home.SendSheet
import dev.tandem.app.settings.SyncFeature
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

private const val NOT_CONNECTED_MESSAGE = "Not connected to your Mac."
private const val CLIPBOARD_OFF_MESSAGE = "Clipboard is turned off."

@Composable
internal fun HomeTab(
    dependencies: AppShellDependencies,
    statusLine: String,
    ringState: HomeRingState,
    modifier: Modifier,
) {
    val scope = rememberCoroutineScope()
    val featureStates by dependencies.featureStates.collectAsState()
    HomeScreen(
        statusLine = statusLine,
        ringState = ringState,
        featureStates = featureStates,
        onFeatureToggled = { feature, enabled -> scope.launch { dependencies.onToggleFeature(feature, enabled) } },
        modifier = modifier,
    )
}

/** The "Send to Mac" sheet the shared cookie FAB opens; sends only while connected. */
@Composable
internal fun ShellSendSheet(
    dependencies: AppShellDependencies,
    snackbarHostState: SnackbarHostState,
    scope: CoroutineScope,
    onDismiss: () -> Unit,
) {
    val featureStates by dependencies.featureStates.collectAsState()
    val sendClipboard =
        whenConnected(dependencies, scope, snackbarHostState) {
            sendClipboardIfOn(featureStates, dependencies, scope, snackbarHostState)
        }
    val sendFiles = whenConnected(dependencies, scope, snackbarHostState, dependencies.onSendFiles)
    SendSheet(
        onDismissRequest = onDismiss,
        onSendClipboard = {
            onDismiss()
            sendClipboard()
        },
        onSendFiles = {
            onDismiss()
            sendFiles()
        },
    )
}

private fun whenConnected(
    dependencies: AppShellDependencies,
    scope: CoroutineScope,
    snackbarHostState: SnackbarHostState,
    action: () -> Unit,
): () -> Unit =
    {
        if (dependencies.isConnected()) {
            action()
        } else {
            scope.launch { snackbarHostState.showSnackbar(NOT_CONNECTED_MESSAGE) }
        }
    }

private fun sendClipboardIfOn(
    featureStates: Map<SyncFeature, Boolean>,
    dependencies: AppShellDependencies,
    scope: CoroutineScope,
    snackbarHostState: SnackbarHostState,
) {
    if (featureStates[SyncFeature.Clipboard] == false) {
        scope.launch { snackbarHostState.showSnackbar(CLIPBOARD_OFF_MESSAGE) }
    } else {
        dependencies.onSendClipboard()
    }
}
