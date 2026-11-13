package dev.tandem.feature.calls

import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.core.transport.time.SystemElapsedRealtimeSource
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Hands the number [TandemCallScreeningService] sees to [TelecomCallGateway]: the screening
 * callback and the telephony state callback race, so either may come first. A number lives only
 * until [clear] (call ended) and is never logged (invariant 7).
 */
class IncomingNumberRelay(
    private val elapsedRealtimeSource: ElapsedRealtimeSource = SystemElapsedRealtimeSource,
) {
    private class Screened(
        val number: String?,
        val publishedAtMillis: Long,
    )

    private val latest = MutableStateFlow<Screened?>(null)

    fun publish(number: String?) {
        latest.value = Screened(number, elapsedRealtimeSource.elapsedRealtimeMillis())
    }

    fun clear() {
        latest.value = null
    }

    /** The screened number if one has arrived, without waiting. */
    fun peek(): String? = latest.value?.takeIf(::isFresh)?.number

    /** Waits up to [timeoutMs] for the screening callback; null when none arrived or it had no number. */
    suspend fun await(timeoutMs: Long): String? =
        withTimeoutOrNull(timeoutMs) { latest.filterNotNull().first(::isFresh) }?.number

    // A number published while no session was attached must not be attributed to a later call.
    private fun isFresh(screened: Screened): Boolean =
        elapsedRealtimeSource.elapsedRealtimeMillis() - screened.publishedAtMillis <= MAX_AGE_MILLIS

    companion object {
        private const val MAX_AGE_MILLIS = 60_000L
        val shared = IncomingNumberRelay()
    }
}
