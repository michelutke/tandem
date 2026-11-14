package dev.tandem.app.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dev.tandem.app.R
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.Banner
import dev.tandem.core.designsystem.components.DotHero
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.TitleBlock

/**
 * Onboarding · Welcome (ui-spec §7.2): dot hero on top, the title pair in the middle, then the
 * no-accounts footnote and a single full-width "Get started" action pinned to the bottom. [revokedBy]
 * (the Mac that removed this phone, ui-spec §8) adds a dismissible banner on top.
 */
@Composable
fun WelcomeScreen(
    onGetStarted: () -> Unit,
    modifier: Modifier = Modifier,
    revokedBy: String? = null,
    onDismissRevoked: () -> Unit = {},
) {
    Scaffold(modifier = modifier, containerColor = TandemColors.paper) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(TandemSpacing.screenPadding),
            horizontalAlignment = Alignment.Start,
        ) {
            if (revokedBy != null) {
                Banner(
                    message = stringResource(R.string.revoked_message, revokedBy),
                    actionLabel = stringResource(R.string.revoked_dismiss),
                    onAction = onDismissRevoked,
                )
            }
            Spacer(Modifier.weight(1f))
            DotHero(modifier = Modifier.align(Alignment.CenterHorizontally))
            Spacer(Modifier.weight(1f))
            TitleBlock(
                title = stringResource(R.string.welcome_title),
                state = stringResource(R.string.welcome_state),
            )
            Spacer(Modifier.weight(2f))
            Column(verticalArrangement = Arrangement.spacedBy(TandemSpacing.md)) {
                Text(
                    text = stringResource(R.string.welcome_footnote),
                    style = TandemType.meta,
                    color = TandemColors.ink,
                )
                PillButton(text = stringResource(R.string.welcome_get_started), onClick = onGetStarted)
            }
        }
    }
}
