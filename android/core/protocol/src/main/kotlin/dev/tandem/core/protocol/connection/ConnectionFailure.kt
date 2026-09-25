package dev.tandem.core.protocol.connection

import dev.tandem.core.protocol.CloseCode

/**
 * Why a [ConnectionStateMachine] reached [ConnectionState.Failed] (E12-08; aligned with the macOS
 * twin, E12-09).
 */
sealed class ConnectionFailure {
    /**
     * No [ConnectionEvent.HandshakeCompleted] arrived within [ConnectionStateMachine.HANDSHAKE_DEADLINE]
     * of [ConnectionEvent.Connect] (SPEC.md #timeouts-connection-limits-and-resource-caps, E01-22:
     * "TLS handshake deadline... 10 s from connect() (phone, dialing)").
     */
    data object Timeout : ConnectionFailure()

    /**
     * Any other handshake or hello-exchange failure reported to this machine via
     * [ConnectionEvent.HandshakeError] (e.g. a TLS failure, or a [message] translated from a
     * [dev.tandem.core.protocol.handshake.HandshakeFailure] reported by the E12-15 `VersionHandshake`
     * this machine wraps).
     */
    data class HandshakeError(
        val message: String,
    ) : ConnectionFailure()
}

/**
 * SPEC.md #errors-and-close-codes close code for [this] failure, where one applies (§10's TLS
 * handshake deadline maps to [CloseCode.PROTOCOL_TIMEOUT]); `null` for [ConnectionFailure.HandshakeError],
 * which has no single close code at this layer — that determination belongs to whichever later
 * issue inspects the underlying TLS/handshake failure (E12-16).
 */
val ConnectionFailure.closeCode: CloseCode?
    get() =
        when (this) {
            ConnectionFailure.Timeout -> CloseCode.PROTOCOL_TIMEOUT
            is ConnectionFailure.HandshakeError -> null
        }
