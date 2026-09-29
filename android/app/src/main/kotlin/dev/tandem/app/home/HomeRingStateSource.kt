package dev.tandem.app.home

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Live source of [HomeRingState] for [HomeViewModel]. Whichever task is running -- transfer,
 * mirroring, ringing -- is this source's responsibility to report and clear; [HomeViewModel]
 * only renders whatever it currently holds.
 */
interface HomeRingStateSource {
    val state: StateFlow<HomeRingState>
}

/**
 * No transfer (Phase 4), mirroring, ringing-progress or synced-today counting data source exists
 * yet to observe -- same gap `MainWindowViewModel`'s caller-supplied connection/disabled state
 * documents on macOS (E22-09), and `MenuBarViewModel`'s own `stateStream: nil` before it. Fixed at
 * [HomeRingState.Idle] with zero counts until a future issue (activity log / transfer / mirroring)
 * wires the real session/status stream this should observe instead.
 */
class StubHomeRingStateSource : HomeRingStateSource {
    override val state: StateFlow<HomeRingState> =
        MutableStateFlow(HomeRingState.Idle(itemsSyncedToday = 0, sevenDayAverage = 0))
}
