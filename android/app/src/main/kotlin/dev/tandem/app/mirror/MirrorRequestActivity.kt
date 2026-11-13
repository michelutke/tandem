package dev.tandem.app.mirror

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dev.tandem.app.R
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemTheme
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.NumberedRow
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.PillButtonVariant
import dev.tandem.core.designsystem.components.TitleBlock
import dev.tandem.core.ui.TandemActivity
import dev.tandem.feature.input.LiveRemoteInput
import dev.tandem.feature.mirror.MirrorPromptActionDispatcher
import dev.tandem.feature.mirror.NotificationMirrorPromptPresenter

/**
 * "Mirror." request screen (ui-spec §7.2), opened from the mirror prompt notification. Start mirroring
 * only hands over to [MirrorConsentActivity], whose tap is the user-initiated start before the system
 * MediaProjection consent (invariant 8); Not now declines through the live prompt controller. Not
 * exported; with no live prompt controller (no paired session) it closes at once. The "Mac can tap and
 * type" fact is shown only while remote input is available (the Accessibility service is connected);
 * otherwise the view-only wording of the "View only." notice replaces it.
 */
class MirrorRequestActivity : TandemActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (MirrorPromptActionDispatcher.controller == null) {
            finish()
            return
        }
        val macName =
            intent.getStringExtra(NotificationMirrorPromptPresenter.EXTRA_PEER_NAME)
                ?: getString(R.string.mirror_peer_fallback_name)
        setContent {
            TandemTheme {
                MirrorRequestScreen(
                    macName = macName,
                    onStart = {
                        startActivity(Intent(this, MirrorConsentActivity::class.java))
                        finish()
                    },
                    onNotNow = {
                        MirrorPromptActionDispatcher.controller?.onDeclineOrDismiss()
                        finish()
                    },
                    remoteInputAvailable = LiveRemoteInput.current != null,
                    modifier = Modifier.fillMaxSize().safeDrawingPadding(),
                )
            }
        }
    }
}

@Composable
fun MirrorRequestScreen(
    macName: String,
    onStart: () -> Unit,
    onNotNow: () -> Unit,
    remoteInputAvailable: Boolean,
    modifier: Modifier = Modifier,
) {
    Scaffold(modifier = modifier, containerColor = TandemColors.paper) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(vertical = TandemSpacing.screenPadding)) {
            TitleBlock(
                title = stringResource(R.string.mirror_request_title),
                state = stringResource(R.string.mirror_request_state, macName),
                modifier = Modifier.padding(horizontal = TandemSpacing.screenPadding),
            )
            Spacer(Modifier.height(TandemSpacing.xl))
            val inputFact =
                if (remoteInputAvailable) R.string.mirror_request_fact_2 else R.string.mirror_view_only_text
            listOf(R.string.mirror_request_fact_1, inputFact, R.string.mirror_request_fact_3)
                .forEachIndexed { index, fact ->
                    HairlineRule(Modifier.padding(horizontal = TandemSpacing.screenPadding))
                    NumberedRow(index = index + 1, label = stringResource(fact))
                }
            HairlineRule(Modifier.padding(horizontal = TandemSpacing.screenPadding))
            Spacer(Modifier.weight(1f))
            Column(
                modifier = Modifier.padding(horizontal = TandemSpacing.screenPadding),
                verticalArrangement = Arrangement.spacedBy(TandemSpacing.sm),
            ) {
                PillButton(text = stringResource(R.string.mirror_request_start), onClick = onStart)
                PillButton(
                    text = stringResource(R.string.mirror_request_not_now),
                    onClick = onNotNow,
                    variant = PillButtonVariant.Secondary,
                )
            }
        }
    }
}
