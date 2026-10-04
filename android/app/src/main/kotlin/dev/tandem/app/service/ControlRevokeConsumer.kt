package dev.tandem.app.service

import dev.tandem.core.pairing.revoke.RevokeHandler
import dev.tandem.core.pairing.revoke.TrustRemover
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import kotlinx.coroutines.flow.firstOrNull

/**
 * Waits for the first `Revoke` on [registered]'s CONTROL channel and hands it to the real
 * [RevokeHandler] (E14-19): trust is deleted via [trustRemover], then the session is closed.
 * A Revoke arriving before Ready is ignored by the handler and the wait continues. Returns without
 * throwing when the session closes first (its CONTROL flow completes).
 *
 * [registered]'s session fans CONTROL out to every subscriber (E20-22), so this runs alongside
 * pairing and rotation consumers without stealing their frames.
 */
suspend fun consumeControlRevoke(
    registered: RegisteredSession,
    trustRemover: TrustRemover,
) {
    val handler = RevokeHandler(registered.session, registered.peer, trustRemover)
    registered.session
        .receive(Channel.CHANNEL_CONTROL)
        .firstOrNull { envelope -> envelope.payloadCase == Envelope.PayloadCase.REVOKE && handler.handleRevoke() }
}
