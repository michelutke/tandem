package dev.tandem.feature.messaging

import dev.tandem.core.transport.time.ElapsedRealtimeSource

/** At most [MAX_SENDS] accepted sends per rolling [WINDOW_MS] (docs/protocol/SPEC.md #sms-channel "Send"). */
class SendRateLimiter(
    private val elapsed: ElapsedRealtimeSource,
) {
    private val accepted = ArrayDeque<Long>()

    @Synchronized
    fun tryAcquire(): Boolean {
        val now = elapsed.elapsedRealtimeMillis()
        while (accepted.isNotEmpty() && now - accepted.first() >= WINDOW_MS) accepted.removeFirst()
        if (accepted.size >= MAX_SENDS) return false
        accepted.addLast(now)
        return true
    }

    companion object {
        const val MAX_SENDS = 10
        const val WINDOW_MS = 60_000L
    }
}
