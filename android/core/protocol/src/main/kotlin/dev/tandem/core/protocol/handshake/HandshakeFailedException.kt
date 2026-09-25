package dev.tandem.core.protocol.handshake

/** Completes [VersionHandshake.awaitReady] exceptionally instead of leaving it suspended forever. */
class HandshakeFailedException(
    val reason: HandshakeFailure,
) : Exception("VersionHandshake failed: $reason")
