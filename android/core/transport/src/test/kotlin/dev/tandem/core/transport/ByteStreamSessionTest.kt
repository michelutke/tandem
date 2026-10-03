package dev.tandem.core.transport

import app.cash.turbine.test
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.core.testing.ManualElapsedRealtime
import dev.tandem.core.transport.heartbeat.DeviceIdleSource
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.heartbeat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import java.time.Clock
import java.util.concurrent.atomic.AtomicReference
import kotlin.time.Duration.Companion.milliseconds
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
    fun byteStreamSession_sendAfterLocalClose_throwsMultiplexerClosedException() =
        sessionTest {
            val pipe = InMemoryDuplexPipe()
            val a = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO)
            val b = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)

            a.state.first { it is ConnectionState.Ready }
            a.close()

            assertThrows(MultiplexerClosedException::class.java) {
                runBlocking { a.send(Channel.CHANNEL_CONTROL) { heartbeat = heartbeat {} } }
            }

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

    @Test
    fun byteStreamSession_peerClosesWhileHeartbeatActive_noCrashAndSessionCloses() =
        sessionTest {
            // E20-15 verifier finding #1 regression: a peer EOF/IOException used to close
            // `ChannelMultiplexer` without anything stopping the heartbeat trio or transitioning
            // this session's own state, and the trio's next send threw `MultiplexerClosedException`
            // uncaught -- on Android that reaches the thread's default `UncaughtExceptionHandler`
            // and crashes the app, which this asserts against directly.
            val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
            val uncaught = AtomicReference<Throwable?>(null)
            Thread.setDefaultUncaughtExceptionHandler { _, throwable -> uncaught.compareAndSet(null, throwable) }
            try {
                val pipe = InMemoryDuplexPipe()
                val dependencies = HeartbeatDependencies(ManualElapsedRealtime(), FakeDeviceIdleSource())
                val a = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO, dependencies)
                val b = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)

                a.state.first { it is ConnectionState.Ready }
                b.state.first { it is ConnectionState.Ready }

                // The heartbeat trio genuinely active -- `a` receives and replies to a heartbeat --
                // then the peer EOFs. `closeGracefully` (FIN-like) rather than `closeAbruptly` so
                // only `a`'s own multiplexer closes here -- `b`'s incoming direction is left open,
                // so this never also crashes `b`'s own reader/writer loops with an unrelated
                // `IOException`, which is no part of this fix. The brief delay lets `a`'s reply
                // actually finish writing before the peer EOFs, so this exercises finding #1's
                // close-while-heartbeat-active wiring without also landing on the pre-existing,
                // separately scoped race where `ChannelMultiplexer`'s writer loop is caught
                // mid-write by this same session's own `byteStream.closeAbruptly()`.
                b.send(Channel.CHANNEL_CONTROL) { heartbeat = heartbeat {} }
                delay(200.milliseconds)
                pipe.endpointB.closeGracefully()

                withTimeout(5.seconds) {
                    a.state.first { it is ConnectionState.Disconnected }
                }

                // Give any in-flight reply attempt -- now caught, not propagated -- a chance to run.
                delay(200.milliseconds)
                assertNull(uncaught.get(), "no exception should escape the heartbeat trio")

                b.close()
            } finally {
                Thread.setDefaultUncaughtExceptionHandler(previousHandler)
            }
        }

    @Test
    fun byteStreamSession_readyThenClose_emitsReadyThenDisconnectedMarkers() =
        sessionTest {
            val pipe = InMemoryDuplexPipe()
            val events = java.util.Collections.synchronizedList(mutableListOf<String>())
            val markers =
                object : ReconnectMarkers {
                    override fun disconnected() {
                        events += "disconnected"
                    }

                    override fun dead() {
                        events += "dead"
                    }

                    override fun ready() {
                        events += "ready"
                    }
                }
            val a = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO, markers = markers)
            val b = ByteStreamSession(pipe.endpointB, Clock.systemUTC(), Dispatchers.IO)

            a.state.first { it is ConnectionState.Ready }
            b.state.first { it is ConnectionState.Ready }
            a.close()
            b.close()

            assertEquals(listOf("ready", "disconnected"), events.toList())
        }

    @Test
    fun byteStreamSession_closeBeforeReady_leavesNoLeakedCoroutine() =
        sessionTest {
            // E20-15 verifier finding #3 regression: `state.first { it is Ready }` suspends forever
            // for a session that never reaches `Ready`, and `close()` used to never cancel `scope`,
            // so that coroutine (and everything it held) leaked. `endpointA` here never gets a peer
            // hello -- nothing else is ever constructed on the other end of the pipe -- so `a` never
            // leaves `HelloExchange`.
            val pipe = InMemoryDuplexPipe()
            val dependencies = HeartbeatDependencies(ManualElapsedRealtime(), FakeDeviceIdleSource())
            val a = ByteStreamSession(pipe.endpointA, Clock.systemUTC(), Dispatchers.IO, dependencies)

            withTimeout(5.seconds) {
                while (pipe.capturedAToB().isEmpty()) delay(10)
            }

            val subscriber =
                launch(start = CoroutineStart.UNDISPATCHED) { a.receive(Channel.CHANNEL_CONTROL).collect { } }
            delay(50)

            a.close()

            withTimeout(5.seconds) { subscriber.join() }
            val sessionJob = a.scope.coroutineContext.job
            withTimeout(5.seconds) {
                while (sessionJob.children.any { it.isActive }) delay(10)
            }
        }

    private class FakeDeviceIdleSource : DeviceIdleSource {
        override val isIdle: StateFlow<Boolean> = MutableStateFlow(false)
        override val screenOn: Flow<Unit> = emptyFlow()
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
