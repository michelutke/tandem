package dev.tandem.core.transport

import app.cash.turbine.test
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Test
import java.time.Clock
import kotlin.time.Duration.Companion.seconds

/**
 * [ByteStreamSession] tests (E12-11; `docs/planning/backlog/phase-1.yaml` E12-11's `tdd:` list).
 * Two real sessions are wired over `InMemoryDuplexPipe` (E00-19), mirroring `ChannelMultiplexerTest`:
 * `runBlocking(Dispatchers.IO)` with real threads, since `InMemoryDuplexPipe` blocks real threads
 * internally (`ReentrantLock`/`Condition`) via `runInterruptible`.
 */
class ByteStreamSessionTest {
    @Test
    fun byteStreamSession_notifySendOverPipe_peerReceivesIdenticalEnvelope() =
        sessionTest {
            val pipe = InMemoryDuplexPipe()
            val a = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO)
            val b = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)

            a.state.first { it is ConnectionState.Ready }
            b.state.first { it is ConnectionState.Ready }

            b.receive(Channel.CHANNEL_NOTIFY).test {
                a.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
                val received = awaitItem()
                assertEquals(Channel.CHANNEL_NOTIFY, received.channel)
                assertEquals(DeviceStatus.getDefaultInstance(), received.deviceStatus)
                cancelAndIgnoreRemainingEvents()
            }

            a.close()
            b.close()
        }

    @Test
    fun byteStreamSession_close_stateDisconnectedAndReceiveCompletes() =
        sessionTest {
            val pipe = InMemoryDuplexPipe()
            val a = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO)
            val b = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)

            a.state.first { it is ConnectionState.Ready }
            b.state.first { it is ConnectionState.Ready }

            a.receive(Channel.CHANNEL_NOTIFY).test {
                a.close()
                awaitComplete()
            }

            assertInstanceOf(ConnectionState.Disconnected::class.java, a.state.value)

            b.close()
        }

    @Test
    fun byteStreamSession_connectionResetWhileAwaitingPeerHello_stateBecomesFailed() =
        sessionTest {
            // E12-13: reproduced against the real Mac listener rejecting an unseeded client's
            // certificate -- the connection resets after this side's own hello is already sent but
            // before the peer's arrives, so `VersionHandshake.perform()`'s `awaitPeerHello()` sees
            // its `inbound` flow close and throws, instead of a peer hello ever showing up.
            val pipe = InMemoryDuplexPipe()
            val client = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO)

            withTimeout(5.seconds) {
                while (pipe.capturedAToB().isEmpty()) delay(10)
            }
            pipe.endpointA.closeAbruptly()

            withTimeout(5.seconds) {
                client.state.first { it is ConnectionState.Failed }
            }

            client.close()
        }

    private companion object {
        fun sessionTest(block: suspend CoroutineScope.() -> Unit) {
            runBlocking(Dispatchers.IO) {
                try {
                    block()
                } finally {
                    coroutineContext.cancelChildren()
                }
            }
        }
    }
}
