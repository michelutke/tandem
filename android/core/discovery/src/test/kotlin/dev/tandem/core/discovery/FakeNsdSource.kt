package dev.tandem.core.discovery

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * Scripted fake of [NsdSource] for [NsdServiceDiscoveryTest]: [emit] drives raw browse events,
 * [scriptResolve] queues the [ResolveOutcome]s [resolve] returns for a given service, one per
 * call, in order. No NsdManager, or real network, is ever involved.
 */
class FakeNsdSource : NsdSource {
    private val browseEvents = KtChannel<NsdBrowseEvent>(KtChannel.UNLIMITED)
    private val scriptedResolves = mutableMapOf<NsdServiceRef, ArrayDeque<ResolveOutcome>>()

    private val mutableResolveAttempts = mutableListOf<NsdServiceRef>()

    /** Every [resolve] call so far, in order, as the [NsdServiceRef] it was called with. */
    val resolveAttempts: List<NsdServiceRef> get() = mutableResolveAttempts.toList()

    /** Queues [outcomes] for [service], returned by successive [resolve] calls, in order. */
    fun scriptResolve(
        service: NsdServiceRef,
        vararg outcomes: ResolveOutcome,
    ) {
        scriptedResolves.getOrPut(service) { ArrayDeque() }.addAll(outcomes)
    }

    /** Emits [event] on [browse], as if NsdManager's discovery listener had produced it. */
    fun emit(event: NsdBrowseEvent) {
        browseEvents.trySend(event)
    }

    override fun browse(serviceType: String): Flow<NsdBrowseEvent> = browseEvents.receiveAsFlow()

    override suspend fun resolve(service: NsdServiceRef): ResolveOutcome {
        mutableResolveAttempts += service
        val queue = scriptedResolves[service] ?: error("no scripted resolve outcome for $service")
        return queue.removeFirstOrNull() ?: error("resolve outcomes exhausted for $service")
    }
}
