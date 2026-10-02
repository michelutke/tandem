package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionFailure

/**
 * Producer of the `"REVOKED"` reason [ConnectionErrorMapper] understands (E20-21, SPEC.md
 * #errors-and-close-codes row 7): a handshake rejection against a peer this device had previously
 * pinned and that then rejects our client key (TLS `certificate_unknown` / `bad_certificate` alert)
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
            CLIENT_KEY_REJECTED_ALERTS.none { failure.message.contains(it, ignoreCase = true) } -> failure
            else -> ConnectionFailure.HandshakeError("REVOKED")
        }

    private val CLIENT_KEY_REJECTED_ALERTS = listOf("certificate_unknown", "bad_certificate")
}
