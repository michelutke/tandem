package dev.tandem.app.mirror

import dev.tandem.feature.input.InputGate
import dev.tandem.feature.input.Size
import dev.tandem.protocol.v1.Envelope

/**
 * Hands each `InputEvent` on the INPUT channel to the round's [gate] (invariant 8). Without a gate
 * (accessibility service not connected) every event is dropped; nothing here executes input itself.
 */
class RemoteInputRouter(
    private val gate: () -> InputGate?,
    private val window: () -> Size,
    private val display: () -> Size,
) {
    fun route(envelope: Envelope) {
        if (!envelope.hasInputEvent()) return
        gate()?.handle(envelope.inputEvent, window(), display())
    }
}
