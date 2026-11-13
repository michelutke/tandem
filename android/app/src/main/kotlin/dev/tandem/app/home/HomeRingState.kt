package dev.tandem.app.home

import androidx.annotation.StringRes
import dev.tandem.app.R

/**
 * What the Home ring (ui-spec.md §6, decision D-55) currently shows. Idle is the default: items
 * synced today. A running task (transfer, mirroring, ringing) takes over the ring the moment it
 * starts, and the ring returns to [Idle] the moment the task ends -- see [HomeRingStateSource] for
 * how this is sourced and [toDotRingContent] for the exact numeral/label/dot mapping.
 */
sealed interface HomeRingState {
    /** Idle: count of items synced today (notifications, clips, files) vs. the 7-day average. */
    data class Idle(
        val itemsSyncedToday: Int,
        val sevenDayAverage: Int,
    ) : HomeRingState

    /** File transfers in progress, aggregated over all of them; never carries a file name. */
    data class Transfer(
        val percent: Int,
        val toMac: Boolean,
    ) : HomeRingState

    /** Shown briefly after the last transfer in one direction finished, before the ring returns to [Idle]. */
    data class TransferDone(
        val toMac: Boolean,
    ) : HomeRingState

    /** Screen mirroring in progress; the ring numeral shows [elapsedSeconds] as `mm:ss`. */
    data class Mirroring(
        val elapsedSeconds: Int,
    ) : HomeRingState

    /** The phone is ringing (find-phone): no numeral, a pulsing ring. */
    data object Ringing : HomeRingState

    /** Reconnecting: seconds to the next attempt, and which attempt this is. */
    data class Reconnecting(
        val secondsToNextAttempt: Int,
        val attemptNumber: Int,
    ) : HomeRingState
}

private const val SECONDS_PER_MINUTE = 60

/** The [dev.tandem.core.designsystem.components.DotRing] params for a [HomeRingState] (ui-spec §6's table). */
internal data class DotRingContent(
    val numeral: String,
    @StringRes val labelRes: Int,
    val litFraction: Float,
    val numeralUnit: String? = null,
    val labelArg: Int? = null,
    val signalFraction: Float? = null,
    val pulse: Boolean = false,
)

/** Maps [HomeRingState] to [DotRingContent] per ui-spec §6's table. */
internal fun HomeRingState.toDotRingContent(): DotRingContent =
    when (this) {
        is HomeRingState.Idle -> {
            DotRingContent(
                numeral = itemsSyncedToday.toString(),
                labelRes = R.string.home_ring_idle,
                litFraction = (itemsSyncedToday.toFloat() / maxOf(sevenDayAverage, 1)).coerceIn(0f, 1f),
            )
        }

        is HomeRingState.Transfer -> {
            DotRingContent(
                numeral = percent.toString(),
                numeralUnit = PERCENT_UNIT,
                labelRes = if (toMac) R.string.home_ring_sending else R.string.home_ring_receiving,
                litFraction = percent / PERCENT_MAX,
            )
        }

        is HomeRingState.TransferDone -> {
            DotRingContent(
                numeral = PERCENT_MAX.toInt().toString(),
                numeralUnit = PERCENT_UNIT,
                labelRes = if (toMac) R.string.home_ring_sent else R.string.home_ring_received,
                litFraction = 1f,
            )
        }

        is HomeRingState.Mirroring -> {
            DotRingContent(
                numeral = "%02d:%02d".format(elapsedSeconds / SECONDS_PER_MINUTE, elapsedSeconds % SECONDS_PER_MINUTE),
                labelRes = R.string.home_ring_mirroring,
                litFraction = 1f,
                signalFraction = (elapsedSeconds % SECONDS_PER_MINUTE) / SECONDS_PER_MINUTE.toFloat(),
            )
        }

        HomeRingState.Ringing -> {
            DotRingContent(numeral = "", labelRes = R.string.home_ring_ringing, litFraction = 0f, pulse = true)
        }

        is HomeRingState.Reconnecting -> {
            DotRingContent(
                numeral = secondsToNextAttempt.toString(),
                numeralUnit = SECONDS_UNIT,
                labelRes = R.string.home_ring_reconnecting,
                labelArg = attemptNumber,
                litFraction = 0f,
            )
        }
    }

private const val PERCENT_UNIT = "%"
private const val SECONDS_UNIT = "s"
private const val PERCENT_MAX = 100f
