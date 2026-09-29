package dev.tandem.app.home

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class FakeHomeRingStateSource(
    initial: HomeRingState = HomeRingState.Idle(itemsSyncedToday = 0, sevenDayAverage = 0),
) : HomeRingStateSource {
    private val mutableState = MutableStateFlow(initial)
    override val state: StateFlow<HomeRingState> = mutableState

    fun emit(state: HomeRingState) {
        mutableState.value = state
    }
}
