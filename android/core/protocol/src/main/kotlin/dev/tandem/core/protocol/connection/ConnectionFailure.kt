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

    /** The peer's protocol `major` differs from ours (SPEC.md close code `VERSION_MISMATCH`). */
    data object VersionMismatch : ConnectionFailure()

    /** This phone's identity key is missing or unreadable while a Mac is paired; nothing can be dialed. */
    data object IdentityUnavailable : ConnectionFailure()

    /**
     * The peer closed the connection with a TLS alert rejecting this phone's client certificate, i.e.
     * it no longer trusts this phone's key (e.g. it unpaired us). Only a typed alert, never a reset,
     * EOF or timeout, produces this.
     */
    data object PeerRejectedCertificate : ConnectionFailure()

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

            ConnectionFailure.VersionMismatch,
            ConnectionFailure.IdentityUnavailable,
            ConnectionFailure.PeerRejectedCertificate,
            is ConnectionFailure.HandshakeError,
            -> null
        }
