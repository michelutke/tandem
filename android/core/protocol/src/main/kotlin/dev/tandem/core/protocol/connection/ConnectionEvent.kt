package dev.tandem.core.protocol.connection

/** Inputs to [ConnectionStateMachine.handle] (E12-08). See [ConnectionState] for the legal transitions. */
sealed class ConnectionEvent {
    /** Dial the peer; legal only from [ConnectionState.Disconnected]. */
    data object Connect : ConnectionEvent()

    /** The TCP socket opened; legal only from [ConnectionState.Connecting]. */
    data object SocketOpened : ConnectionEvent()

    /** The TLS handshake completed; legal only from [ConnectionState.TlsHandshaking]. */
    data object HandshakeCompleted : ConnectionEvent()

    /** A version-compatible peer `VersionHello` was received; legal only from [ConnectionState.HelloExchange]. */
    data object CompatibleHelloReceived : ConnectionEvent()

    /** The peer's hello carried a different protocol `major`; legal from any state, like [HandshakeError]. */
    data object VersionMismatch : ConnectionEvent()

    /** The peer rejected this phone's client certificate with a TLS alert; legal from any state. */
    data object PeerRejectedCertificate : ConnectionEvent()

    /** The peer's hello did not arrive within the hello-exchange deadline; legal from any state. */
    data object HelloTimeout : ConnectionEvent()

    /**
     * A handshake or hello-exchange failure; legal from any state, always moves to
     * [ConnectionState.Failed] (acceptance: "Every Failed state carries a non-empty reason").
     */
    data class HandshakeError(
        val message: String,
    ) : ConnectionEvent() {
        init {
            require(message.isNotBlank()) { "HandshakeError message must not be blank" }
        }
    }

    /** The underlying socket closed; illegal only once [ConnectionState.Disconnected] or [ConnectionState.Failed]. */
    data class SocketClosed(
        val reason: String,
    ) : ConnectionEvent()
}
