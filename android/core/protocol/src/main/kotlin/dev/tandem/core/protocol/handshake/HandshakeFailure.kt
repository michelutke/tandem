package dev.tandem.core.protocol.handshake

/**
 * Why [VersionHandshake.perform] reached [HandshakeOutcome.Failed] (SPEC.md
 * #versioning-and-capability-negotiation, #timeouts-connection-limits-and-resource-caps E01-22;
 * aligned with the macOS twin, E12-07's `HandshakeFailure`). Neither case tears down the
 * connection itself — SPEC.md's close codes `VERSION_MISMATCH` and `PROTOCOL_TIMEOUT` are for
 * whichever later issue actually owns closing the socket (E12-08) to produce from these.
 */
sealed class HandshakeFailure {
    /** The peer's `major` differs from [VersionHandshake.PROTOCOL_MAJOR] (SPEC.md close code `VERSION_MISMATCH`). */
    data class VersionMismatch(
        val peerMajor: Int,
        val peerMinor: Int,
    ) : HandshakeFailure()

    /**
     * No peer `VersionHello` arrived within [VersionHandshake.HELLO_DEADLINE] (SPEC.md close code
     * `PROTOCOL_TIMEOUT`).
     */
    data object Timeout : HandshakeFailure()
}
