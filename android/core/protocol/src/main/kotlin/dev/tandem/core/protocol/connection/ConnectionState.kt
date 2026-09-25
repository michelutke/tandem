package dev.tandem.core.protocol.connection

import java.time.Instant

/**
 * Phone-side control-connection lifecycle (E12-08; SPEC.md #timeouts-connection-limits-and-resource-caps
 * E01-22, #errors-and-close-codes E01-05; aligned with the macOS twin, E12-09's `ConnectionState`).
 * Documented transitions, all driven by [ConnectionStateMachine.handle]:
 *
 * [Disconnected] -[Connect]-> [Connecting] -[SocketOpened]-> [TlsHandshaking]
 * -[HandshakeCompleted]-> [HelloExchange] -[CompatibleHelloReceived]-> [Ready]
 * -[SocketClosed]-> [Disconnected]
 *
 * [Failed] is reachable from any state on [ConnectionEvent.HandshakeError] or on
 * [ConnectionStateMachine.HANDSHAKE_DEADLINE] elapsing (SPEC.md E01-22). No other event is legal
 * from a state it is not listed above: [ConnectionStateMachine.handle] leaves the state unchanged
 * and reports the event as rejected instead.
 */
sealed class ConnectionState {
    /** Initial state, and the state reached after [ConnectionEvent.SocketClosed] on a [Ready] session. */
    data class Disconnected(
        val reason: String? = null,
    ) : ConnectionState()

    /** Dialing: the TCP connect() this machine's [ConnectionStateMachine.HANDSHAKE_DEADLINE] is measured from. */
    data object Connecting : ConnectionState()

    /** The TCP socket is open and the TLS handshake is in progress. */
    data object TlsHandshaking : ConnectionState()

    /** TLS completed; awaiting the E12-15 `VersionHello` exchange over CONTROL. */
    data object HelloExchange : ConnectionState()

    /**
     * Both hellos exchanged and version-compatible. [connectedAt] is this side's own
     * [ConnectionStateMachine]-injected `Clock` reading.
     */
    data class Ready(
        val connectedAt: Instant,
    ) : ConnectionState()

    /** See [ConnectionFailure] for why. */
    data class Failed(
        val reason: ConnectionFailure,
    ) : ConnectionState()
}
