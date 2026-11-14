package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.transport.ClientCertificateAlerts

/**
 * Producer of the `"REVOKED"` reason [ConnectionErrorMapper] understands (E20-21, SPEC.md
 * #errors-and-close-codes row 7): a handshake rejection against a peer this device had previously
 * pinned and that then rejects our client key (a TLS client-certificate rejection alert, see [ClientCertificateAlerts])
 * means that peer unpaired us. Every other handshake failure is left alone.
 */
object ConnectionFailureClassifier {
    fun classify(
        failure: ConnectionFailure,
        wasPreviouslyPinned: Boolean,
    ): ConnectionFailure =
        when {
            failure !is ConnectionFailure.HandshakeError -> failure
            !wasPreviouslyPinned -> failure
            ClientCertificateAlerts.NAMES.none { failure.message.contains(it, ignoreCase = true) } -> failure
            else -> REVOKED
        }

    /**
     * A session that failed before Ready against a peer this device had previously pinned: under
     * TLS 1.3 the peer's client-certificate rejection arrives after the TLS connect, as a session
     * failure, so only the typed [ConnectionFailure.PeerRejectedCertificate] reads as REVOKED. Any
     * other failure (a reset, EOF, version mismatch or timeout) keeps its own category.
     */
    fun classifySettled(
        failure: ConnectionFailure,
        wasPreviouslyPinned: Boolean,
    ): ConnectionFailure =
        if (wasPreviouslyPinned && failure is ConnectionFailure.PeerRejectedCertificate) REVOKED else failure

    private val REVOKED = ConnectionFailure.HandshakeError("REVOKED")
}
