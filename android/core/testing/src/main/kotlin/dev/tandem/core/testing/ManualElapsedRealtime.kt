package dev.tandem.core.testing

import dev.tandem.core.transport.time.ElapsedRealtimeSource

/**
 * [ElapsedRealtimeSource] a test advances by hand, independent of any `TestCoroutineScheduler`
 * (E00-18) -- unlike [FakeElapsedRealtime], which is deliberately tied 1:1 to a scheduler's own
 * virtual time. Use this where a test needs to simulate elapsed (sleep-inclusive) time moving
 * *without* the coroutine dispatcher's virtual time moving with it -- e.g. proving a dead-peer
 * detector's Doze-exit/screen-on check fires from silence alone, before its own `delay`-based timer
 * (driven by dispatcher virtual time) would ever get a chance to.
 */
class ManualElapsedRealtime(
    initialMillis: Long = 0,
) : ElapsedRealtimeSource {
    private var millis = initialMillis

    override fun elapsedRealtimeMillis(): Long = millis

    fun advanceBy(deltaMillis: Long) {
        millis += deltaMillis
    }
}
