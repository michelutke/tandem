package dev.tandem.core.transport

import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.revoke
import dev.tandem.protocol.v1.rotationChallenge
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import kotlinx.coroutines.channels.Channel as KtChannel

class ChannelDispatcherTest {
    private fun TestScope.dispatcherOver(inbound: KtChannel<Envelope>): ChannelDispatcher =
        ChannelDispatcher(CoroutineScope(StandardTestDispatcher(testScheduler))) { inbound.receiveAsFlow() }

    private val revokeFrame =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            revoke = revoke {}
        }
    private val rotationFrame =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            rotationChallenge = rotationChallenge {}
        }

    private fun CoroutineScope.firstOn(dispatcher: ChannelDispatcher) =
        async(start = CoroutineStart.UNDISPATCHED) { dispatcher.subscribe(Channel.CHANNEL_CONTROL).first() }

    private fun CoroutineScope.allOn(dispatcher: ChannelDispatcher) =
        async(start = CoroutineStart.UNDISPATCHED) { dispatcher.subscribe(Channel.CHANNEL_CONTROL).toList() }

    @Test
    fun controlDispatcher_concurrentRevokeAndRotationSubscribers_eachReceivesItsFrame() =
        runTest {
            val inbound = KtChannel<Envelope>(KtChannel.UNLIMITED)
            val dispatcher = dispatcherOver(inbound)
            val revoked =
                async(start = CoroutineStart.UNDISPATCHED) {
                    dispatcher
                        .subscribe(Channel.CHANNEL_CONTROL)
                        .first { it.payloadCase == Envelope.PayloadCase.REVOKE }
                }
            val rotated =
                async(start = CoroutineStart.UNDISPATCHED) {
                    dispatcher
                        .subscribe(Channel.CHANNEL_CONTROL)
                        .first { it.payloadCase == Envelope.PayloadCase.ROTATION_CHALLENGE }
                }

            inbound.trySend(rotationFrame)
            inbound.trySend(revokeFrame)
            advanceUntilIdle()

            assertEquals(revokeFrame, revoked.await())
            assertEquals(rotationFrame, rotated.await())
        }

    @Test
    fun channelDispatcher_framesBeforeFirstSubscriber_heldForIt() =
        runTest {
            val inbound = KtChannel<Envelope>(KtChannel.UNLIMITED)
            val dispatcher = dispatcherOver(inbound)
            inbound.trySend(revokeFrame)
            inbound.trySend(rotationFrame)
            inbound.close()

            val received = dispatcher.subscribe(Channel.CHANNEL_CONTROL).toList()

            assertEquals(listOf(revokeFrame, rotationFrame), received)
        }

    @Test
    fun channelDispatcher_sourceCompletes_everySubscriberFlowCompletes() =
        runTest {
            val inbound = KtChannel<Envelope>(KtChannel.UNLIMITED)
            val dispatcher = dispatcherOver(inbound)
            val first = allOn(dispatcher)
            val second = allOn(dispatcher)

            inbound.trySend(revokeFrame)
            inbound.close()
            advanceUntilIdle()

            assertEquals(listOf(revokeFrame), first.await())
            assertEquals(listOf(revokeFrame), second.await())
            assertEquals(emptyList<Envelope>(), dispatcher.subscribe(Channel.CHANNEL_CONTROL).toList())
        }

    @Test
    fun channelDispatcher_cancelledSubscriber_doesNotStallOthers() =
        runTest {
            val inbound = KtChannel<Envelope>(KtChannel.UNLIMITED)
            val dispatcher = dispatcherOver(inbound)
            val leaving = firstOn(dispatcher)
            val staying = allOn(dispatcher)

            inbound.trySend(revokeFrame)
            advanceUntilIdle()
            assertEquals(revokeFrame, leaving.await())
            inbound.trySend(rotationFrame)
            inbound.close()
            advanceUntilIdle()

            assertEquals(listOf(revokeFrame, rotationFrame), staying.await())
        }

    @Test
    fun channelDispatcher_stalledSubscriber_pullsAtMostOneFrameAhead() =
        runTest {
            val pulled = mutableListOf<Envelope>()
            val inbound = KtChannel<Envelope>(KtChannel.UNLIMITED)
            val dispatcher =
                ChannelDispatcher(CoroutineScope(StandardTestDispatcher(testScheduler))) {
                    inbound.receiveAsFlow().onEach { pulled += it }
                }
            val gate = CompletableDeferred<Unit>()
            val stalled =
                async(start = CoroutineStart.UNDISPATCHED) {
                    val seen = mutableListOf<Envelope>()
                    dispatcher.subscribe(Channel.CHANNEL_CONTROL).collect {
                        seen += it
                        gate.await()
                    }
                    seen
                }
            repeat(5) { inbound.trySend(revokeFrame) }
            advanceUntilIdle()

            assertEquals(2, pulled.size)

            gate.complete(Unit)
            inbound.close()
            advanceUntilIdle()
            assertEquals(5, stalled.await().size)
            assertEquals(5, pulled.size)
        }
}
