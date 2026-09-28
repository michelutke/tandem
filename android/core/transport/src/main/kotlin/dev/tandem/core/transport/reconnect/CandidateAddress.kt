package dev.tandem.core.transport.reconnect

/**
 * A dial hint for [ReconnectStrategy] (E20-06): [host] literal, [port]. Equality is by
 * [host]/[port] only, so the same address discovered through two sources (e.g. last-working and
 * Bonjour) collapses to one entry when a reconnect cycle is built (invariant 3, CLAUDE.md: this
 * type never carries any notion of trust -- [ReconnectStrategy] always routes it through
 * [Connector], which alone decides whether the peer answering there is the pinned one).
 */
data class CandidateAddress(
    val host: String,
    val port: Int,
)
