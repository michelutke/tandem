package dev.tandem.core.transport.reconnect

import dev.tandem.core.transport.heartbeat.DeviceIdleSource
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.launch
import java.time.Clock
import java.time.Duration
import java.time.Instant

/**
 * Kicks [ReconnectStrategy] when the phone wakes: screen on, Doze exit, or the app returning to
 * the foreground ([foreground]). Without it a dead peer detected across a sleep walks the whole
 * backoff ladder while the network (e.g. a VPN) is still coming back. Same leading-edge 500 ms
 * debounce as [NetworkReconnectTrigger]; [ReconnectStrategy.kick] is a no-op unless the strategy is
 * waiting out a backoff. The initial [DeviceIdleSource.isIdle] value is not an event. Holds no wake
 * lock and changes no heartbeat timing.
 */
class WakeReconnectTrigger(
    private val deviceIdleSource: DeviceIdleSource,
    private val reconnectStrategy: ReconnectStrategy,
    private val clock: Clock,
    dispatcher: CoroutineDispatcher,
    private val foreground: Flow<Unit> = emptyFlow(),
    private val debounceWindow: Duration = DEFAULT_DEBOUNCE_WINDOW,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var job: Job? = null
    private var lastKickAt: Instant? = null

    /** Starts collecting the wake signals. Idempotent: replaces any existing collector. */
    fun start() {
        job?.cancel()
        lastKickAt = null
        job =
            scope.launch {
                merge(
                    deviceIdleSource.screenOn,
                    deviceIdleSource.isIdle
                        .drop(1)
                        .filter { !it }
                        .map { },
                    foreground,
                ).collect {
                    val now = clock.instant()
                    val last = lastKickAt
                    if (last == null || Duration.between(last, now) >= debounceWindow) {
                        lastKickAt = now
                        reconnectStrategy.kick()
                    }
                }
            }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    /** Stops collecting and cancels this instance's scope. */
    fun close() {
        scope.cancel()
    }

    private companion object {
        val DEFAULT_DEBOUNCE_WINDOW: Duration = Duration.ofMillis(500)
    }
}
