package dev.tandem.core.transport.time

import android.os.SystemClock

/**
 * Sleep-inclusive monotonic time in milliseconds (E00-18). Used where wall time is wrong and
 * `System.nanoTime` stops during deep sleep, e.g. dead-peer detection across Doze (E20-15).
 * Inject it; tests use `FakeElapsedRealtime` from `core/testing`.
 */
fun interface ElapsedRealtimeSource {
    fun elapsedRealtimeMillis(): Long
}

/** Production implementation backed by [SystemClock.elapsedRealtime]. */
object SystemElapsedRealtimeSource : ElapsedRealtimeSource {
    override fun elapsedRealtimeMillis(): Long = SystemClock.elapsedRealtime()
}
