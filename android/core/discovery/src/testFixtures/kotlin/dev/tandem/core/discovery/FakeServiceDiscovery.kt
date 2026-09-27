package dev.tandem.core.discovery

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * Scripted fake of [ServiceDiscovery] (E21-04) for tests of code that consumes discovered
 * candidates (E21-05, E20-06): [emit] pushes a [DiscoveryEvent] on [browse] as if a real browse
 * session had produced it, with no NsdManager, and no real network, ever involved.
 */
class FakeServiceDiscovery : ServiceDiscovery {
    private val events = KtChannel<DiscoveryEvent>(KtChannel.UNLIMITED)

    override fun browse(): Flow<DiscoveryEvent> = events.receiveAsFlow()

    /** Emits [event] on [browse], as if the underlying discovery session had produced it. */
    fun emit(event: DiscoveryEvent) {
        events.trySend(event)
    }
}
