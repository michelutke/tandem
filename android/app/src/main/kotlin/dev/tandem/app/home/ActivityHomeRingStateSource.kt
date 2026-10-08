package dev.tandem.app.home

import dev.tandem.app.activity.ActivityEntry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId

/**
 * The idle Home ring (ui-spec §6, D-55) from the Activity feed: items synced today against the
 * average of the 7 retained days.
 */
class ActivityHomeRingStateSource(
    entries: Flow<List<ActivityEntry>>,
    clock: Clock,
    scope: CoroutineScope,
    zone: ZoneId = ZoneId.systemDefault(),
) : HomeRingStateSource {
    override val state: StateFlow<HomeRingState> =
        entries
            .map { list -> idleState(list, LocalDate.now(clock.withZone(zone)), zone) }
            .stateIn(scope, SharingStarted.Eagerly, HomeRingState.Idle(itemsSyncedToday = 0, sevenDayAverage = 0))

    private fun idleState(
        entries: List<ActivityEntry>,
        today: LocalDate,
        zone: ZoneId,
    ): HomeRingState {
        val todayCount = entries.count { it.timestamp.atZone(zone).toLocalDate() == today }
        val average = (entries.size + DAYS_RETAINED - 1) / DAYS_RETAINED
        return HomeRingState.Idle(itemsSyncedToday = todayCount, sevenDayAverage = average)
    }

    private companion object {
        const val DAYS_RETAINED = 7
    }
}
