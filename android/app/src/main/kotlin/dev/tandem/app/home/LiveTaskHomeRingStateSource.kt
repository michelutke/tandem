package dev.tandem.app.home

import dev.tandem.core.transport.time.ElapsedRealtimeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlin.time.Duration

/** What the connection loop is doing while it is not connected: [wait] is the current backoff, null while dialing. */
data class ReconnectProgress(
    val failedCycles: Int,
    val wait: Duration?,
)

/**
 * Lets the live tasks take over [base]'s ring (ui-spec §6): reconnecting while the link is down and
 * the loop has failed at least once, ringing, then mirroring with an `mm:ss` clock. Transfers
 * already arrive through [base].
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LiveTaskHomeRingStateSource(
    base: HomeRingStateSource,
    reconnect: Flow<ReconnectProgress?>,
    mirroring: Flow<Boolean>,
    ringing: Flow<Boolean>,
    private val elapsedRealtime: ElapsedRealtimeSource,
    scope: CoroutineScope,
) : HomeRingStateSource {
    override val state: StateFlow<HomeRingState> =
        combine(
            base.state,
            reconnect.flatMapLatest(::reconnectingRing),
            ringing,
            mirroring.flatMapLatest { if (it) mirroringRing() else flowOf(null) },
        ) { idleOrTransfer, reconnecting, isRinging, mirror ->
            when {
                reconnecting != null -> reconnecting
                isRinging -> HomeRingState.Ringing
                mirror != null -> mirror
                else -> idleOrTransfer
            }
        }.stateIn(scope, SharingStarted.Eagerly, base.state.value)

    private fun reconnectingRing(progress: ReconnectProgress?): Flow<HomeRingState?> =
        flow {
            if (progress == null || (progress.failedCycles == 0 && progress.wait == null)) {
                emit(null)
                return@flow
            }
            val attempt = progress.failedCycles + if (progress.wait != null) NEXT_ATTEMPT_OFFSET else 1
            val endMillis = elapsedRealtime.elapsedRealtimeMillis() + (progress.wait?.inWholeMilliseconds ?: 0L)
            while (true) {
                val remaining = (endMillis - elapsedRealtime.elapsedRealtimeMillis()).coerceAtLeast(0L)
                emit(HomeRingState.Reconnecting(secondsCeil(remaining), attempt))
                if (remaining == 0L) return@flow
                delay(TICK_MILLIS)
            }
        }

    private fun mirroringRing(): Flow<HomeRingState?> =
        flow {
            val start = elapsedRealtime.elapsedRealtimeMillis()
            while (true) {
                val seconds = ((elapsedRealtime.elapsedRealtimeMillis() - start) / TICK_MILLIS).toInt()
                emit(HomeRingState.Mirroring(seconds))
                delay(TICK_MILLIS)
            }
        }

    private fun secondsCeil(millis: Long): Int = ((millis + TICK_MILLIS - 1) / TICK_MILLIS).toInt()

    private companion object {
        const val TICK_MILLIS = 1_000L
        const val NEXT_ATTEMPT_OFFSET = 2
    }
}
