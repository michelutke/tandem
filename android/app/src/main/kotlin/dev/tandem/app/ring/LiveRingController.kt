package dev.tandem.app.ring

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * The [RingController] of the attached session (E20-24), for the ring notification's Stop action:
 * the framework constructs [RingStopActionReceiver], so it reads it from here. Null means no live
 * session. [ringing] mirrors whether the alarm is sounding, for the Home ring.
 */
object LiveRingController {
    @Volatile
    var current: RingController? = null

    internal val mutableRinging = MutableStateFlow(false)
    val ringing: StateFlow<Boolean> = mutableRinging
}
