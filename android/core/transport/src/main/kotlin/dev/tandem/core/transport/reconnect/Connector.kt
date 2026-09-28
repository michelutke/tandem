package dev.tandem.core.transport.reconnect

/**
 * Dials one [CandidateAddress] for [ReconnectStrategy] (E20-06). CRITICAL (invariant 3, CLAUDE.md):
 * every implementation MUST run the full mTLS handshake and pin check against the SPKI fingerprint
 * pinned at pairing time before returning anything other than [ConnectResult.PinMismatch] or
 * [ConnectResult.Unreachable] -- [CandidateAddress]'s source (last-working, Bonjour or pairing-time)
 * is never itself a reason to trust what answers there. [ConnectResult.PinMismatch] MUST be
 * returned before a single byte of application data is exchanged with whatever answered: a host
 * now answering on a previously-working address with a different key is exactly [ConnectResult.PinMismatch],
 * never [ConnectResult.Connected], regardless of address history.
 */
fun interface Connector {
    suspend fun connect(candidate: CandidateAddress): ConnectResult
}

/** Outcome of one [Connector.connect] attempt. */
sealed class ConnectResult {
    /** The full mTLS handshake completed and the peer's SPKI fingerprint matched the pinned one. */
    data object Connected : ConnectResult()

    /** The peer's SPKI fingerprint did not match the pinned one; zero application bytes were sent. */
    data object PinMismatch : ConnectResult()

    /** The address could not be reached (connect timeout, refused, host unreachable, etc). */
    data object Unreachable : ConnectResult()
}
