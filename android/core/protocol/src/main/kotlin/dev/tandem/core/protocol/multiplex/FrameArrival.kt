package dev.tandem.core.protocol.multiplex

import dev.tandem.protocol.v1.Channel

/**
 * One frame [ChannelMultiplexer] has accepted off the wire, broadcast on [ChannelMultiplexer.received]
 * (E20-15; aligned with the macOS twin's `FrameArrival`, E20-05). [isHeartbeat] lets a liveness
 * responder decide whether to reply without reaching back into the full `Envelope`.
 */
data class FrameArrival(
    val channel: Channel,
    val isHeartbeat: Boolean,
)
