package dev.tandem.app.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.components.DotHero
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.TandemScaffold

internal const val WELCOME_TITLE = "Tandem."
internal const val WELCOME_STATE = "Your phone, on your Mac. Privately."
internal const val WELCOME_GET_STARTED_LABEL = "Get started"

/** Onboarding · Welcome (ui-spec §7.2): dot hero, title pair and a single "Get started" action. */
@Composable
fun WelcomeScreen(
    onGetStarted: () -> Unit,
    modifier: Modifier = Modifier,
) {
    TandemScaffold(title = WELCOME_TITLE, state = WELCOME_STATE, modifier = modifier) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = TandemSpacing.screenPadding),
            verticalArrangement = Arrangement.spacedBy(TandemSpacing.lg, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            DotHero()
            PillButton(text = WELCOME_GET_STARTED_LABEL, onClick = onGetStarted)
        }
    }
}
