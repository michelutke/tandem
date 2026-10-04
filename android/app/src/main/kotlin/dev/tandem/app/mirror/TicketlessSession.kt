package dev.tandem.app.mirror

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.flow.Flow

/**
 * [session] minus `RequestMediaTicket` sends. `MediaDialer` requests its own ticket and the Mac
 * supersedes an outstanding ticket on every new request (SPEC.md #media-ticket), so the prompt
 * controller's request would race the dialer's and could invalidate the ticket it dials with.
 */
class TicketlessSession(
    private val session: TandemSession,
) : TandemSession by session {
    override suspend fun send(
        channel: Channel,
        payload: EnvelopeKt.Dsl.() -> Unit,
    ) {
        if (envelope { payload() }.hasRequestMediaTicket()) return
        session.send(channel, payload)
    }

    override fun receive(channel: Channel): Flow<Envelope> = session.receive(channel)
}
