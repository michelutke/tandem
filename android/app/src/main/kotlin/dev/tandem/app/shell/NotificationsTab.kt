package dev.tandem.app.shell

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dev.tandem.app.R
import dev.tandem.app.di.AppDispatchers
import dev.tandem.app.onboarding.rememberResumeCount
import dev.tandem.app.settings.AppPermission
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.TandemLoadingIndicator
import dev.tandem.core.designsystem.components.TandemScaffold
import dev.tandem.feature.notifications.PerAppFilterRow
import dev.tandem.feature.notifications.PerAppNotificationFilterScreen
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
internal fun NotificationsTab(
    dependencies: AppShellDependencies,
    modifier: Modifier,
) {
    val resumeCount by rememberResumeCount()
    val accessOn = resumeCount.let { dependencies.permissions.isGranted(AppPermission.NOTIFICATION_ACCESS) }
    if (accessOn) {
        NotificationAppsList(dependencies, modifier)
    } else {
        NotificationAccessOff(
            onAllowAccess = { dependencies.permissions.request(AppPermission.NOTIFICATION_ACCESS) },
            modifier = modifier,
        )
    }
}

@Composable
internal fun NotificationAccessOff(
    onAllowAccess: () -> Unit,
    modifier: Modifier = Modifier,
) {
    TandemScaffold(
        title = stringResource(R.string.notifications_title),
        state = stringResource(R.string.notifications_access_off),
        isError = true,
        modifier = modifier,
    ) { padding ->
        Column(
            modifier = Modifier.padding(padding).padding(horizontal = TandemSpacing.screenPadding),
            verticalArrangement = Arrangement.spacedBy(TandemSpacing.lg),
        ) {
            Text(
                text = stringResource(R.string.notifications_access_off_explanation),
                style = TandemType.body,
                color = TandemColors.ink2,
            )
            PillButton(text = stringResource(R.string.notifications_allow_access), onClick = onAllowAccess)
        }
    }
}

@Composable
private fun NotificationAppsList(
    dependencies: AppShellDependencies,
    modifier: Modifier,
) {
    var rows by remember { mutableStateOf<List<PerAppFilterRow>?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { rows = withContext(AppDispatchers.io) { dependencies.notificationRows() } }
    val loaded = rows.orEmpty()
    TandemScaffold(
        title = stringResource(R.string.notifications_title),
        state = if (rows == null) "Loading apps." else "${loaded.count { it.allowed }} of ${loaded.size} apps.",
        modifier = modifier,
    ) { padding ->
        if (rows == null) {
            Box(modifier = Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                TandemLoadingIndicator()
            }
        } else {
            PerAppNotificationFilterScreen(
                rows = loaded,
                onToggle = { packageName, allowed ->
                    rows = loaded.map { if (it.packageName == packageName) it.copy(allowed = allowed) else it }
                    scope.launch { dependencies.onToggleNotificationApp(packageName, allowed) }
                },
                modifier = Modifier.padding(padding),
            )
        }
    }
}
