package dev.tandem.app.connection

import dev.tandem.app.service.SessionRegistry
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class OrchestratorConnectionStateTest {
    private val peer = SpkiFingerprint(ByteArray(32) { 4 })

    @Test
    fun state_noSession_disconnected() =
        runTest(UnconfinedTestDispatcher()) {
            val state =
                orchestratorConnectionState(SessionRegistry(), MutableStateFlow(null), backgroundScope)

            assertTrue(state.value is ConnectionState.Disconnected)
        }

    @Test
    fun state_registeredReadySession_ready() =
        runTest(UnconfinedTestDispatcher()) {
            val registry = SessionRegistry()
            val state = orchestratorConnectionState(registry, MutableStateFlow(null), backgroundScope)
            val session = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }

            registry.register(session, peer)

            assertTrue(state.value is ConnectionState.Ready)
        }

    @Test
    fun state_failurePresent_failedWithThatReason() =
        runTest(UnconfinedTestDispatcher()) {
            val failure = MutableStateFlow<ConnectionFailure?>(null)
            val state = orchestratorConnectionState(SessionRegistry(), failure, backgroundScope)
            val pinMismatch = ConnectionFailure.HandshakeError("PIN_MISMATCH")

            failure.value = pinMismatch

            assertEquals(ConnectionState.Failed(pinMismatch), state.value)
        }
}
