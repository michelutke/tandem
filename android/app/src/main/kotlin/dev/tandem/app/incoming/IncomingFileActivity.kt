package dev.tandem.app.incoming

import android.os.Bundle
import android.text.format.Formatter
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dev.tandem.app.R
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemTheme
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.PillButtonVariant
import dev.tandem.core.designsystem.components.TitleBlock
import dev.tandem.core.ui.TandemActivity
import dev.tandem.feature.files.NotificationTransferPrompter
import dev.tandem.feature.files.TransferActionDispatcher

private const val SCRIM_ALPHA = 0.5f

/**
 * "From Mac." sheet (ui-spec §7.2, Incoming file), opened from the file-offer notification. Accept and
 * Decline go to the live [dev.tandem.feature.files.AcceptFlow], exactly as the notification actions do.
 * Not exported; with no live accept flow (no paired session) it closes at once.
 */
class IncomingFileActivity : TandemActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val offerId = intent.getStringExtra(NotificationTransferPrompter.EXTRA_OFFER_ID)
        val name = intent.getStringExtra(NotificationTransferPrompter.EXTRA_DISPLAY_NAME)
        if (offerId == null || name == null || TransferActionDispatcher.acceptFlow == null) {
            finish()
            return
        }
        val size = intent.getLongExtra(NotificationTransferPrompter.EXTRA_SIZE_BYTES, 0L)
        setContent {
            TandemTheme {
                IncomingFileSheet(
                    name = name,
                    size = Formatter.formatShortFileSize(this, size),
                    onAccept = {
                        TransferActionDispatcher.acceptFlow?.accept(offerId)
                        finish()
                    },
                    onDecline = {
                        TransferActionDispatcher.acceptFlow?.decline(offerId)
                        finish()
                    },
                    onDismiss = ::finish,
                )
            }
        }
    }
}

@Composable
@Suppress("LongParameterList") // name, size and the three sheet actions
fun IncomingFileSheet(
    name: String,
    size: String,
    onAccept: () -> Unit,
    onDecline: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier =
            modifier
                .fillMaxSize()
                .background(TandemColors.ink.copy(alpha = SCRIM_ALPHA))
                .clickable(onClick = onDismiss),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Surface(
            modifier = Modifier.fillMaxWidth().clickable(enabled = false) {},
            shape = TandemShapes.sheet,
            color = TandemColors.paper,
        ) {
            Column(
                modifier = Modifier.navigationBarsPadding().padding(TandemSpacing.screenPadding),
                verticalArrangement = Arrangement.spacedBy(TandemSpacing.sm),
            ) {
                TitleBlock(
                    title = stringResource(R.string.incoming_title),
                    state = stringResource(R.string.incoming_state, name, size),
                )
                HairlineRule(Modifier.padding(top = TandemSpacing.md))
                Row(
                    modifier = Modifier.fillMaxWidth().heightIn(min = TandemSpacing.touchTarget),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = stringResource(R.string.incoming_save_to),
                        style = TandemType.rowTitle,
                        color = TandemColors.ink,
                    )
                    Text(
                        text = stringResource(R.string.incoming_save_path),
                        style = TandemType.metaMono,
                        color = TandemColors.ink2,
                    )
                }
                HairlineRule(Modifier.padding(bottom = TandemSpacing.sm))
                PillButton(text = stringResource(R.string.incoming_accept), onClick = onAccept)
                PillButton(
                    text = stringResource(R.string.incoming_decline),
                    onClick = onDecline,
                    variant = PillButtonVariant.Secondary,
                )
            }
        }
    }
}
