package dev.tandem.core.protocol.multiplex

import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope

/**
 * One frame [ChannelMultiplexer] has routed to [ChannelMultiplexer.inbound] (E11-05; aligned with
 * the macOS twin, E11-06's `InboundFrame`). [channel], [seq] and [ack] are pulled out of [payload]
 * for convenience — they are always equal to `payload.channel`/`payload.seq`/`payload.ack` — since
 * a consumer of a single channel's flow otherwise has to reach back into the full [Envelope] for
 * values it already knows.
 */
data class InboundFrame(
    val channel: Channel,
    val seq: Long,
    val ack: Long,
    val payload: Envelope,
)
