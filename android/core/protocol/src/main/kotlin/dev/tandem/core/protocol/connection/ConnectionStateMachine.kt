package dev.tandem.core.protocol.connection

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Clock
import kotlin.time.Duration.Companion.seconds

/**
 * Phone-side control-connection state machine (E12-08; SPEC.md #timeouts-connection-limits-and-resource-caps
 * E01-22, invariant 5; aligned with the macOS twin, E12-09). Pure and synchronous except for the
 * [HANDSHAKE_DEADLINE] timer: [handle] applies [ConnectionEvent]s to [ConnectionState] and updates
 * [state] immediately, so every transition in [ConnectionState]'s kdoc is exercised without
 * suspending — the sole exception is the deadline armed by [ConnectionEvent.Connect] and
 * disarmed by [ConnectionEvent.HandshakeCompleted]/[ConnectionEvent.HandshakeError], which runs on
 * the injected [dispatcher] so it is exercised in virtual time under `runTest` + `TestClock`
 * (E00-18, E00-04).
 *
 * [clock] stamps [ConnectionState.Ready.connectedAt]; it plays no part in the deadline mechanism
 * itself; that mechanism, like [dev.tandem.core.protocol.handshake.VersionHandshake]'s own 5 s
 * deadline, is [delay]-based so it advances with whichever [CoroutineDispatcher] `runTest` gives
 * this class in tests.
 *
 * An illegal event — one not listed as legal from the current state in [ConnectionState]'s kdoc —
 * leaves [state] unchanged; [handle] returns `false` to report it as rejected.
 */
class ConnectionStateMachine(
    private val clock: Clock,
    dispatcher: CoroutineDispatcher,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)

    private val mutableState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected())
    val state: StateFlow<ConnectionState> = mutableState.asStateFlow()

    private var deadline: Job? = null

    /**
     * Applies [event] to the current state. Returns `false`, leaving [state] unchanged, if
     * [event] is illegal from it.
     */
    fun handle(event: ConnectionEvent): Boolean {
        val next = transition(mutableState.value, event) ?: return false
        applyDeadline(event)
        mutableState.value = next
        return true
    }

    /** Cancels the deadline timer, if any. Callers own this machine's lifetime and MUST call this once done with it. */
    fun close() {
        scope.cancel()
    }

    private fun transition(
        current: ConnectionState,
        event: ConnectionEvent,
    ): ConnectionState? =
        when (event) {
            is ConnectionEvent.HandshakeError -> {
                ConnectionState.Failed(ConnectionFailure.HandshakeError(event.message))
            }

            ConnectionEvent.Connect -> {
                if (current is ConnectionState.Disconnected) ConnectionState.Connecting else null
            }

            ConnectionEvent.SocketOpened -> {
                if (current is ConnectionState.Connecting) ConnectionState.TlsHandshaking else null
            }

            ConnectionEvent.HandshakeCompleted -> {
                if (current is ConnectionState.TlsHandshaking) ConnectionState.HelloExchange else null
            }

            ConnectionEvent.CompatibleHelloReceived -> {
                if (current is ConnectionState.HelloExchange) ConnectionState.Ready(clock.instant()) else null
            }

            is ConnectionEvent.SocketClosed -> {
                if (current is ConnectionState.Ready) ConnectionState.Disconnected(event.reason) else null
            }
        }

    private fun applyDeadline(event: ConnectionEvent) {
        when (event) {
            ConnectionEvent.Connect -> armDeadline()
            ConnectionEvent.HandshakeCompleted, is ConnectionEvent.HandshakeError -> disarmDeadline()
            else -> Unit
        }
    }

    private fun armDeadline() {
        deadline =
            scope.launch {
                delay(HANDSHAKE_DEADLINE)
                mutableState.value = ConnectionState.Failed(ConnectionFailure.Timeout)
            }
    }

    private fun disarmDeadline() {
        deadline?.cancel()
        deadline = null
    }

    companion object {
        /** SPEC.md #timeouts-connection-limits-and-resource-caps, E01-22: "10 s from connect() (phone, dialing)". */
        val HANDSHAKE_DEADLINE = 10.seconds
    }
}
