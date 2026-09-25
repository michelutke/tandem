package dev.tandem.core.protocol.connection

import app.cash.turbine.test
import dev.tandem.core.protocol.CloseCode
import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * ConnectionStateMachine tests (E12-08; `docs/planning/backlog/phase-1.yaml` E12-08's `tdd:`
 * list). Every machine here is built from a `TestClock`/`StandardTestDispatcher` pair sharing one
 * `TestCoroutineScheduler`, so the 10 s handshake deadline advances in virtual time under
 * `runTest` (E00-18, E00-04); transitions are asserted with Turbine against `state`, a `StateFlow`
 * that emits its current value the moment `.test {}` starts collecting.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ConnectionStateMachineTest {
    @Test
    fun connectionSm_connectWhileDisconnected_emitsConnecting() =
        runTest {
            val sm = newMachine()

            sm.state.test {
                assertEquals(ConnectionState.Disconnected(), awaitItem())
                assertTrue(sm.handle(ConnectionEvent.Connect))
                assertEquals(ConnectionState.Connecting, awaitItem())
            }
        }

    @Test
    fun connectionSm_socketOpened_emitsTlsHandshaking() =
        runTest {
            val sm = newMachine()
            sm.handle(ConnectionEvent.Connect)

            sm.state.test {
                assertEquals(ConnectionState.Connecting, awaitItem())
                assertTrue(sm.handle(ConnectionEvent.SocketOpened))
                assertEquals(ConnectionState.TlsHandshaking, awaitItem())
            }
        }

    @Test
    fun connectionSm_handshakeCompleted_emitsHelloExchange() =
        runTest {
            val sm = newMachine()
            sm.handle(ConnectionEvent.Connect)
            sm.handle(ConnectionEvent.SocketOpened)

            sm.state.test {
                assertEquals(ConnectionState.TlsHandshaking, awaitItem())
                assertTrue(sm.handle(ConnectionEvent.HandshakeCompleted))
                assertEquals(ConnectionState.HelloExchange, awaitItem())
            }
        }

    @Test
    fun connectionSm_compatibleHelloReceived_emitsReady() =
        runTest {
            val sm = newMachine()
            sm.handle(ConnectionEvent.Connect)
            sm.handle(ConnectionEvent.SocketOpened)
            sm.handle(ConnectionEvent.HandshakeCompleted)

            sm.state.test {
                assertEquals(ConnectionState.HelloExchange, awaitItem())
                assertTrue(sm.handle(ConnectionEvent.CompatibleHelloReceived))
                val ready = awaitItem() as ConnectionState.Ready
                assertEquals(TestClock(testScheduler).instant(), ready.connectedAt)
            }
        }

    @Test
    fun connectionSm_handshakeErrorInAnyState_emitsFailedWithNonEmptyReason() =
        runTest {
            val startingStates =
                listOf(
                    ConnectionEvent.Connect,
                    ConnectionEvent.SocketOpened,
                    ConnectionEvent.HandshakeCompleted,
                    ConnectionEvent.CompatibleHelloReceived,
                )

            // From Disconnected, and from every state reachable by replaying an increasing prefix
            // of the happy-path events, HandshakeError always moves to Failed.
            for (prefixLength in 0..startingStates.size) {
                val sm = newMachine()
                startingStates.take(prefixLength).forEach { sm.handle(it) }

                sm.state.test {
                    skipItems(1)
                    assertTrue(sm.handle(ConnectionEvent.HandshakeError("tls failure")))
                    val failed = awaitItem() as ConnectionState.Failed
                    val reason = failed.reason as ConnectionFailure.HandshakeError
                    assertTrue(reason.message.isNotEmpty())
                    assertEquals("tls failure", reason.message)
                }
            }
        }

    @Test
    fun connectionSm_socketClosedWhileReady_emitsDisconnectedWithReason() =
        runTest {
            val sm = newMachine()
            sm.handle(ConnectionEvent.Connect)
            sm.handle(ConnectionEvent.SocketOpened)
            sm.handle(ConnectionEvent.HandshakeCompleted)
            sm.handle(ConnectionEvent.CompatibleHelloReceived)

            sm.state.test {
                assertTrue(awaitItem() is ConnectionState.Ready)
                assertTrue(sm.handle(ConnectionEvent.SocketClosed("peer closed the connection")))
                assertEquals(ConnectionState.Disconnected("peer closed the connection"), awaitItem())
            }
        }

    @Test
    fun connectionSm_handshakeStartedWhileReady_rejectedStateUnchanged() =
        runTest {
            val sm = newMachine()
            sm.handle(ConnectionEvent.Connect)
            sm.handle(ConnectionEvent.SocketOpened)
            sm.handle(ConnectionEvent.HandshakeCompleted)
            sm.handle(ConnectionEvent.CompatibleHelloReceived)

            sm.state.test {
                assertTrue(awaitItem() is ConnectionState.Ready)
                assertFalse(sm.handle(ConnectionEvent.SocketOpened))
                expectNoEvents()
            }
        }

    @Test
    fun connectionSm_handshakeTimeoutElapsed_emitsFailedTimeout() =
        runTest {
            val sm = newMachine()

            sm.state.test {
                assertEquals(ConnectionState.Disconnected(), awaitItem())
                sm.handle(ConnectionEvent.Connect)
                assertEquals(ConnectionState.Connecting, awaitItem())

                advanceTimeBy(ConnectionStateMachine.HANDSHAKE_DEADLINE)
                runCurrent()

                val failed = awaitItem() as ConnectionState.Failed
                assertEquals(ConnectionFailure.Timeout, failed.reason)
                assertEquals(CloseCode.PROTOCOL_TIMEOUT, failed.reason.closeCode)
            }
        }

    private fun TestScope.newMachine(): ConnectionStateMachine =
        ConnectionStateMachine(TestClock(testScheduler), StandardTestDispatcher(testScheduler))
}
