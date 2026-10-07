package dev.tandem.app.shell

import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import dev.tandem.app.home.HomeRingState
import dev.tandem.app.home.HomeScreen
import dev.tandem.app.settings.SyncFeature
import dev.tandem.core.designsystem.components.FloatingToolbarItem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

private const val NOT_CONNECTED_MESSAGE = "Not connected to your Mac."
private const val CLIPBOARD_OFF_MESSAGE = "Clipboard is turned off."

@Composable
@Suppress("LongParameterList") // shell state the Home route reads
internal fun HomeTab(
    navigator: AppShellNavigator,
    dependencies: AppShellDependencies,
    statusLine: String,
    ringState: HomeRingState,
    snackbarHostState: SnackbarHostState,
    modifier: Modifier,
) {
    val scope = rememberCoroutineScope()
    val featureStates by dependencies.featureStates.collectAsState()
    val sendClipboard =
        whenConnected(dependencies, scope, snackbarHostState) {
            sendClipboardIfOn(featureStates, dependencies, scope, snackbarHostState)
        }
    val sendFiles = whenConnected(dependencies, scope, snackbarHostState, dependencies.onSendFiles)
    HomeScreen(
        statusLine = statusLine,
        ringState = ringState,
        selectedToolbarItem = FloatingToolbarItem.Home,
        onToolbarItemSelected = navigator::select,
        onSendClipboard = sendClipboard,
        onSendFiles = sendFiles,
        featureStates = featureStates,
        onFeatureToggled = { feature, enabled -> scope.launch { dependencies.onToggleFeature(feature, enabled) } },
        modifier = modifier,
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
