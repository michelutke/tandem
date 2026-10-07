package dev.tandem.core.pairing

/**
 * Thrown by a [PairingConnector] when this phone's own identity key could not be created or used,
 * so no mTLS dial was attempted. [PairingStateMachine] maps it to [PairingFailure.IdentityUnavailable]
 * without trying further addresses. Carries no message: key-store errors stay out of logs (invariant 7).
 */
class IdentityUnavailableException(
    cause: Throwable? = null,
) : RuntimeException(null, cause)
