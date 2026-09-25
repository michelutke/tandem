package dev.tandem.core.protocol.handshake

/**
 * Result of [VersionHandshake.perform] (E12-15; aligned with the macOS twin's result type, E12-07).
 */
sealed class HandshakeOutcome {
    /** Both hellos exchanged and version-compatible (SPEC.md #versioning-and-capability-negotiation). */
    data class Ready(
        val session: NegotiatedSession,
    ) : HandshakeOutcome()

    /** See [HandshakeFailure] for why. */
    data class Failed(
        val reason: HandshakeFailure,
    ) : HandshakeOutcome()
}
