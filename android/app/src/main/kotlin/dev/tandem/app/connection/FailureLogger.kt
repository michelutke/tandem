package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionFailure

/**
 * Formats connection failures for logging without exposing secrets (invariant 7).
 */
object FailureLogger {
    /**
     * Format a failure for logging.
     * Returns category and reason without any certificate bytes, keys, or secrets.
     */
    fun formatLogEntry(failure: ConnectionFailure): String =
        when (failure) {
            ConnectionFailure.Timeout -> {
                "Timeout"
            }

            is ConnectionFailure.HandshakeError -> {
                // Extract reason category without exposing message content if it contains cert bytes
                when {
                    failure.message.contains("PIN_MISMATCH") -> {
                        "PIN_MISMATCH"
                    }

                    failure.message.contains("VERSION_MISMATCH") -> {
                        "VERSION_MISMATCH"
                    }

                    failure.message.contains("REVOKED") -> {
                        "REVOKED"
                    }

                    failure.message.contains("TIMEOUT") -> {
                        "TIMEOUT"
                    }

                    else -> {
                        "HANDSHAKE_ERROR"
                    }
                }
            }
        }
}
