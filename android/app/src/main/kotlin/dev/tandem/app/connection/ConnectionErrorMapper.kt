package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionFailure

/**
 * Maps [ConnectionFailure] to user-visible error messages (E12-16).
 * Invariant 5: fail closed with visible error, no plaintext secrets in messages.
 */
object ConnectionErrorMapper {
    /**
     * The notice shown after this phone's identity was reset: the Mac still pins the old key and
     * pairing is refused while a trust record exists, so the user must unpair first.
     */
    fun identityResetMessage(macName: String?): String =
        "This phone's security key was reset. Unpair ${macName ?: "your Mac"}, then pair again."

    /**
     * Map a connection failure to an error message.
     *
     * @param failure The connection failure reason
     * @param macName Optional Mac display name for REVOKED errors
     * @return A user-visible error message
     */
    fun mapToErrorMessage(
        failure: ConnectionFailure,
        macName: String? = null,
    ): String =
        when (failure) {
            ConnectionFailure.Timeout -> {
                "Connection timed out. Check your network and try again."
            }

            ConnectionFailure.IdentityUnavailable -> {
                "This phone's security key is unavailable. Restart the app, or unpair this Mac and pair again if " +
                    "this persists."
            }

            ConnectionFailure.VersionMismatch -> {
                "Version mismatch. Check for app updates."
            }

            ConnectionFailure.PeerRejectedCertificate -> {
                "Connection failed. Please try again."
            }

            is ConnectionFailure.HandshakeError -> {
                when {
                    failure.message.contains("REVOKED") && macName != null -> {
                        "This device is no longer paired with $macName."
                    }

                    failure.message.contains("REVOKED") -> {
                        "This device is no longer paired."
                    }

                    failure.message.contains("PIN_MISMATCH") -> {
                        "The PIN doesn't match. This device is not trusted."
                    }

                    else -> {
                        "Connection failed. Please try again."
                    }
                }
            }
        }
}
