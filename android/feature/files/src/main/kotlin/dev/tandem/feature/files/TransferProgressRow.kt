package dev.tandem.feature.files

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType

/** In-flight transfer row (E40-12): integer percent, speed, progress bar and Cancel. */
@Composable
fun TransferProgressRow(
    progress: TransferProgress,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val speed = Formatter.formatShortFileSize(LocalContext.current, progress.bytesPerSecond)
    Column(modifier = modifier.fillMaxWidth().padding(vertical = TandemSpacing.rowVerticalPadding)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(text = "${progress.percent}%", style = TandemType.rowTitle, color = TandemColors.ink)
            Text(text = "$speed/s", style = TandemType.metaMono, color = TandemColors.ink2)
            TextButton(onClick = onCancel) {
                Text(text = stringResource(R.string.files_progress_cancel), color = TandemColors.ink)
            }
        }
        LinearProgressIndicator(
            progress = { progress.percent / PERCENT_SCALE },
            modifier = Modifier.fillMaxWidth(),
            color = TandemColors.signal,
            trackColor = TandemColors.lineUnlitDot,
        )
    }
}

private const val PERCENT_SCALE = 100f
