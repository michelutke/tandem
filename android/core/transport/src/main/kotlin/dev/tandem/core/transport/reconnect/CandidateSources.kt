package dev.tandem.core.transport.reconnect

/**
 * Bonjour-resolved addresses of recognized paired Macs (E21-05) currently known to
 * [ReconnectStrategy] (E20-06). [snapshot] is a hint only (invariant 3, CLAUDE.md): recognizing a
 * service's rotating id only earns it a place in the dial order, never any trust.
 * [PairedMacBonjourSource] is the production implementation, backed by
 * `dev.tandem.core.discovery.ServiceDiscovery` and `dev.tandem.core.discovery.PairedMacMatcher`.
 */
fun interface BonjourCandidateSource {
    fun snapshot(): List<CandidateAddress>
}

/**
 * Addresses recorded at pairing time (the QR payload's `PairingInvite.addresses`/`port`,
 * `core/pairing`) for [ReconnectStrategy] (E20-06). Also a hint only (invariant 3, CLAUDE.md).
 *
 * Deviation note (E20-06): nothing in `core/storage`'s `PeerRecord` persists these addresses today
 * -- `TrustCommitter.commit` only takes a fingerprint, display name and `pairedAt`. Persisting them
 * is not part of this issue's scope (it touches the trust store schema and the pairing commit
 * path, not the reconnect state machine); this interface is the seam a follow-up wires a real
 * source through. Until then, a caller with no persisted addresses may supply one that always
 * returns an empty list.
 */
fun interface PairingAddressSource {
    fun addresses(): List<CandidateAddress>
}
