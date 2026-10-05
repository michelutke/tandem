package dev.tandem.app.ring

/**
 * The [RingController] of the attached session (E20-24), for the ring notification's Stop action:
 * the framework constructs [RingStopActionReceiver], so it reads it from here. Null means no live
 * session.
 */
object LiveRingController {
    @Volatile
    var current: RingController? = null
}
