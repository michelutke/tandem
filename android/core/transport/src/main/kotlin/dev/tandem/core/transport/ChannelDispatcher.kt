package dev.tandem.core.transport

import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * Per-session inbound fan-out (E20-22): the only collector of each channel's single-consumer
 * [source] flow, so any number of independent consumers (pairing, rotation, Revoke, file accept /
 * send, sync sessions, ...) can [subscribe] to the same [Channel] without stealing each other's
 * frames.
 *
 * Semantics, per channel:
 * - Every frame is delivered to every subscriber registered when it is delivered; subscribers
 *   filter by payload themselves. A subscriber registered before a frame is delivered never misses
 *   it: delivery suspends until the subscriber takes it, so the slowest subscriber paces the
 *   channel and the underlying credit replenishment (SPEC.md D-64) keeps its backpressure.
 * - Nothing is pulled from [source] until the first [subscribe] collects, and while no subscriber
 *   is registered the frame in hand is held (not dropped) until one registers. So frames sent
 *   before the first subscriber are buffered by [source] as before.
 * - Late subscribers see only frames delivered after they register (no replay) while at least one
 *   other subscriber was present. A caller that must not miss a reply sent right after subscribing
 *   registers first: collect `UNDISPATCHED` (`async(start = CoroutineStart.UNDISPATCHED)`), then send.
 * - When [source] completes or fails, every subscriber's flow completes, and later subscribers
 *   complete immediately.
 */
class ChannelDispatcher(
    private val scope: CoroutineScope,
    private val source: (Channel) -> Flow<Envelope>,
) {
    private val lanes = ConcurrentHashMap<Channel, Lane>()

    /** Frames on [channel] delivered while the returned flow is being collected. */
    fun subscribe(channel: Channel): Flow<Envelope> =
        flow {
            val lane = lanes.computeIfAbsent(channel) { Lane(it) }
            val subscription = lane.register() ?: return@flow
            lane.start()
            try {
                for (envelope in subscription) emit(envelope)
            } finally {
                lane.unregister(subscription)
            }
        }

    private inner class Lane(
        private val channel: Channel,
    ) {
        private val lock = Any()
        private val subscribers = MutableStateFlow<List<KtChannel<Envelope>>>(emptyList())
        private var completed = false
        private var started = false

        fun register(): KtChannel<Envelope>? =
            synchronized(lock) {
                if (completed) return null
                KtChannel<Envelope>().also { subscription -> subscribers.update { it + subscription } }
            }

        fun unregister(subscription: KtChannel<Envelope>) {
            subscribers.update { it - subscription }
            subscription.cancel()
        }

        fun start() {
            synchronized(lock) {
                if (started) return
                started = true
            }
            scope.launch { run() }.invokeOnCompletion { complete() }
        }

        @Suppress("TooGenericExceptionCaught") // a failed source ends the lane like a closed one
        private suspend fun run() {
            try {
                source(channel).collect { envelope ->
                    subscribers.first { it.isNotEmpty() }.forEach { deliver(it, envelope) }
                }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Exception) {
                return
            }
        }

        @Suppress("SwallowedException") // the subscriber left mid-delivery; only a cancelled lane stops
        private suspend fun deliver(
            subscription: KtChannel<Envelope>,
            envelope: Envelope,
        ) {
            try {
                subscription.send(envelope)
            } catch (cancellation: CancellationException) {
                currentCoroutineContext().ensureActive()
            }
        }

        private fun complete() {
            val toClose =
                synchronized(lock) {
                    completed = true
                    subscribers.value
                }
            toClose.forEach { it.close() }
        }
    }
}
