package dev.tandem.app.home

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

    /** A file transfer in progress; [fileName] is peer-provided and must already be sanitised (ui-spec §9.7). */
    data class Transfer(
        val percent: Int,
        val fileName: String,
        val toMac: Boolean,
    ) : HomeRingState

    /**
     * Screen mirroring in progress. ui-spec §6 wants the numeral formatted `mm:ss`; [DotRing][dev.tandem.core.designsystem.components.DotRing]
     * only renders an `Int` numeral, so this is rendered as raw elapsed seconds until a future
     * issue extends `DotRing` with a formatted-numeral slot (documented gap, [toDotRingContent]).
     */
    data class Mirroring(
        val elapsedSeconds: Int,
    ) : HomeRingState

    /**
     * The phone is ringing (find-phone). ui-spec §6 wants no numeral and a pulsing dot ring;
     * [DotRing][dev.tandem.core.designsystem.components.DotRing] has neither a numeral-less mode
     * nor a pulse animation, so this renders as an unlit ring with a `0` placeholder numeral until
     * a future issue extends it (documented gap, [toDotRingContent]).
     */
    data object Ringing : HomeRingState

    /** Reconnecting: seconds to the next attempt, and which attempt this is. */
    data class Reconnecting(
        val secondsToNextAttempt: Int,
        val attemptNumber: Int,
    ) : HomeRingState
}

/** The [dev.tandem.core.designsystem.components.DotRing] params for a [HomeRingState] (ui-spec §6's table). */
internal data class DotRingContent(
    val value: Int,
    val maxValue: Int,
    val unit: String,
)

/**
 * Maps [HomeRingState] to [DotRing][dev.tandem.core.designsystem.components.DotRing] params per
 * ui-spec §6's table. `maxValue = 0` forces `DotRing`'s internal fraction to `0`, which lights no
 * dots -- i.e. all-grey -- matching the "Reconnecting: all unlit" / "Mirroring, Ringing: no known
 * progress" rows without needing a separate "force grey" knob on `DotRing` itself.
 */
internal fun HomeRingState.toDotRingContent(): DotRingContent =
    when (this) {
        is HomeRingState.Idle -> {
            DotRingContent(
                value = itemsSyncedToday,
                maxValue = maxOf(sevenDayAverage, 1),
                unit = "synced today",
            )
        }

        is HomeRingState.Transfer -> {
            DotRingContent(
                value = percent,
                maxValue = 100,
                unit = "$fileName ${if (toMac) "→ Mac" else "from Mac"}",
            )
        }

        is HomeRingState.Mirroring -> {
            DotRingContent(value = elapsedSeconds, maxValue = 0, unit = "mirroring")
        }

        HomeRingState.Ringing -> {
            DotRingContent(value = 0, maxValue = 0, unit = "ringing")
        }

        is HomeRingState.Reconnecting -> {
            DotRingContent(
                value = secondsToNextAttempt,
                maxValue = 0,
                unit = "next try · attempt $attemptNumber",
            )
        }
    }
