package dev.tandem.core.protocol.handshake

import java.time.Instant

/**
 * The result of a successful [VersionHandshake] (SPEC.md #versioning-and-capability-negotiation,
 * D-63): the peer's advertised `minor` version and its raw `capabilities` bitmask — exposed
 * as-is, unknown bits included, since a receiver "MUST NOT act on any bit" but "MAY... record or
 * expose the raw value" (SPEC.md "Capability mismatch"). [negotiatedAt] is this side's own
 * [VersionHandshake]-injected `Clock` reading (E00-18) at the moment negotiation completed, for
 * callers that want to record it (e.g. alongside a trust-store peer's `lastSeen`, E12-14/E12-17).
 */
data class NegotiatedSession(
    val peerMinor: Int,
    val capabilities: Long,
    val negotiatedAt: Instant,
)
