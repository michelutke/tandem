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

    /** The underlying socket closed; legal only from [ConnectionState.Ready]. */
    data class SocketClosed(
        val reason: String,
    ) : ConnectionEvent()
}
