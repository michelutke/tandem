package dev.tandem.core.transport.reconnect

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Exponential backoff between [ReconnectStrategy] (E20-06) full cycles: 1 s, doubling, capped at
 * 30 s (1, 2, 4, 8, 16, 30, 30, ...).
 */
object ReconnectBackoff {
    /** Cap on the wait between cycles. */
    val MAX_DELAY: Duration = 30.seconds

    private const val MAX_DOUBLINGS = 5 // 2^5 = 32s, already past the 30s cap

    /** The wait after [failedCycles] consecutive failed full cycles (0-indexed: the first failure). */
    fun delayFor(failedCycles: Int): Duration {
        val doublings = failedCycles.coerceIn(0, MAX_DOUBLINGS)
        return (1L shl doublings).seconds.coerceAtMost(MAX_DELAY)
    }
}
