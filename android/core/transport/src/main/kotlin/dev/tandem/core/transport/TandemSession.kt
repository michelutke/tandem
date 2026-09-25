package dev.tandem.core.transport

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

/**
 * Transport-agnostic control-connection session (E12-11; SPEC.md #framing-and-envelope,
 * #channels-and-flow-control-credits; aligned with the macOS twin, E12-12). [ByteStreamSession] is
 * the sole production implementation, wiring a `ByteStream` (SSLSocket in production, E12-04;
 * `InMemoryDuplexPipe` in tests, E00-19) through E12-08's `ConnectionStateMachine`,
 * `VersionHandshake` and `ChannelMultiplexer`; `FakeTandemSession` is the seam every feature test
 * uses instead. No signature here may reference a `javax.net.ssl` or `org.conscrypt` type
 * (`tandemSessionInterface_reflectedSignatures_noSslOrConscryptTypes`), so a future USB transport
 * (F-10.3) can implement this interface without touching feature code.
 *
 * Cycle 8 (D-67, supersedes the original Cycle 4 `channelBinding` property): this interface
 * exposes no `channelBinding` property and no exporter API of any kind — channel binding is not a
 * transport concern. `cb` is the in-band `PairChallenge`/`RotationChallenge` value, generated,
 * sent and held entirely by the pairing (E14-02, E14-05/E14-06) and key-rotation (E70) layers,
 * which read it from an ordinary received [Envelope] like any other CONTROL message, never from
 * this session interface.
 */
interface TandemSession {
    /** This session's connection lifecycle (E12-08); the last-emitted value is the current state. */
    val state: StateFlow<ConnectionState>

    /**
     * Sends one frame on [channel]: [payload] sets the payload, mirroring
     * [dev.tandem.core.protocol.multiplex.ChannelMultiplexer.send]. Suspends until [channel] has
     * outstanding send credit (feature channels only, SPEC.md D-64) and, for any channel but
     * CONTROL, until the E12-15 `VersionHello` exchange has completed.
     */
    suspend fun send(
        channel: Channel,
        payload: EnvelopeKt.Dsl.() -> Unit,
    )

    /** Frames this session has routed for [channel] — never anything routed for a different channel. */
    fun receive(channel: Channel): Flow<Envelope>

    /** Tears down this session: moves [state] to `Disconnected` and completes every [receive] flow. */
    fun close()
}
