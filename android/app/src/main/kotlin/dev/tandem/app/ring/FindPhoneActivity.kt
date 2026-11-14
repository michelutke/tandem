package dev.tandem.app.ring

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import dev.tandem.app.R
import dev.tandem.app.TandemApplication
import dev.tandem.app.di.AppDispatchers
import dev.tandem.core.designsystem.DarkSystemBars
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemTheme
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.DotRing
import dev.tandem.core.ui.TandemActivity
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

private val RING_DIAMETER = 320.dp

/**
 * "Ringing." screen (ui-spec §7.2, Find phone ringing), opened from the ring notification and shown
 * over the lock screen. "Found it" stops the alarm through the live [RingController], the same call
 * as the notification's Stop action. Not exported; closes when the alarm is not sounding.
 */
class FindPhoneActivity : TandemActivity() {
    internal var dispatcher: CoroutineDispatcher = AppDispatchers.default

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        if (!LiveRingController.ringing.value) {
            finish()
            return
        }
        val macNames = (application as TandemApplication).trustStore.observeList().map { it.firstOrNull()?.displayName }
        setContent {
            TandemTheme {
                val ringing by LiveRingController.ringing.collectAsState()
                val macName by macNames.collectAsState(initial = null)
                LaunchedEffect(ringing) { if (!ringing) finish() }
                FindPhoneScreen(
                    macName = macName ?: getString(R.string.mirror_peer_fallback_name),
                    onFoundIt = {
                        CoroutineScope(SupervisorJob() + dispatcher).launch {
                            LiveRingController.current?.dismissedByPhone()
                        }
                        finish()
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }
}

@Composable
fun FindPhoneScreen(
    macName: String,
    onFoundIt: () -> Unit,
    modifier: Modifier = Modifier,
) {
    DarkSystemBars()
    Surface(modifier = modifier, color = TandemColors.paperDark) {
        Column(modifier = Modifier.safeDrawingPadding().padding(TandemSpacing.screenPadding)) {
            Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
                Text(
                    text = stringResource(R.string.ringing_title),
                    style = TandemType.titleEmphasis,
                    color = TandemColors.inkOnDark,
                )
                Text(
                    text = stringResource(R.string.ringing_state, macName),
                    style = TandemType.titleState,
                    color = TandemColors.inkOnDark.copy(alpha = 0.7f),
                )
            }
            Spacer(Modifier.weight(1f))
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                DotRing(
                    numeral = "",
                    label = "",
                    pulse = true,
                    onDark = true,
                    signalInnerRing = true,
                    diameter = RING_DIAMETER,
                    modifier = Modifier.size(RING_DIAMETER),
                )
            }
            Spacer(Modifier.weight(1f))
            Button(
                onClick = onFoundIt,
                modifier = Modifier.fillMaxWidth().heightIn(min = TandemSpacing.touchTarget),
                shape = TandemShapes.button,
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = TandemColors.inkOnDark,
                        contentColor = TandemColors.paperDark,
                    ),
            ) {
                Text(text = stringResource(R.string.ringing_found_it), style = TandemType.rowTitle)
            }
        }
    }
}
