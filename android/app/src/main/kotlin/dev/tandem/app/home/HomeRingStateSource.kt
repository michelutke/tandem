package dev.tandem.app.home

import kotlinx.coroutines.flow.StateFlow

/**
 * Live source of [HomeRingState] for [HomeViewModel]. Whichever task is running -- transfer,
 * mirroring, ringing -- is this source's responsibility to report and clear; [HomeViewModel]
 * only renders whatever it currently holds.
 */
interface HomeRingStateSource {
    val state: StateFlow<HomeRingState>
}
