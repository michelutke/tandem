package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionFailure

/**
 * Producer of the `"REVOKED"` reason [ConnectionErrorMapper] understands (E20-21, SPEC.md
 * #errors-and-close-codes row 7): a handshake rejection against a peer this device had previously
 * pinned means that peer unpaired us. A version mismatch is a different failure and is left alone.
 */
object ConnectionFailureClassifier {
    fun classify(
        failure: ConnectionFailure,
        wasPreviouslyPinned: Boolean,
    ): ConnectionFailure =
        when {
            failure !is ConnectionFailure.HandshakeError -> failure
            !wasPreviouslyPinned -> failure
            failure.message.contains("VERSION_MISMATCH") -> failure
            else -> ConnectionFailure.HandshakeError("REVOKED")
        }
}
