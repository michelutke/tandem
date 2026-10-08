package dev.tandem.feature.calls

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Hands the number [TandemCallScreeningService] sees to [TelecomCallGateway]: the screening
 * callback and the telephony state callback race, so either may come first. A number lives only
 * until [clear] (call ended) and is never logged (invariant 7).
 */
class IncomingNumberRelay {
    private class Screened(
        val number: String?,
    )

    private val latest = MutableStateFlow<Screened?>(null)

    fun publish(number: String?) {
        latest.value = Screened(number)
    }

    fun clear() {
        latest.value = null
    }

    /** The screened number if one has arrived, without waiting. */
    fun peek(): String? = latest.value?.number

    /** Waits up to [timeoutMs] for the screening callback; null when none arrived or it had no number. */
    suspend fun await(timeoutMs: Long): String? =
        withTimeoutOrNull(timeoutMs) { latest.filterNotNull().first() }?.number

    companion object {
        val shared = IncomingNumberRelay()
    }
}
