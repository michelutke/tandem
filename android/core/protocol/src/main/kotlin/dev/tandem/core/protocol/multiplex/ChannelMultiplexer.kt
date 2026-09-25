package dev.tandem.core.protocol.multiplex

import dev.tandem.core.protocol.CloseCode
import dev.tandem.core.protocol.DecodeResult
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.core.protocol.FrameSink
import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.protocol.MalformedFrameReason
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.IOException
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * Channel multiplexer (E11-05; aligned with the macOS twin, E11-06): routes decoded [Envelope]s to
 * per-channel inbound sinks and assigns outgoing `seq`/`ack` per SPEC.md #framing-and-envelope
 * (`docs/planning/decisions.md` D-57). Reads through [FrameSource] and writes through [FrameSink]
 * rather than `core/transport`'s `ByteStream` directly (this module has no dependency on
 * `core/transport`, mirroring [FrameDecoder]/[FrameEncoder]).
 *
 * Structured concurrency: [start] is this multiplexer's single reader loop — callers launch it
 * once, in whichever scope/dispatcher owns the underlying connection (this class never picks its
 * own dispatcher, so it never needs one injected). [send] may be called concurrently from any
 * number of coroutines; a single internal [Mutex] serializes every outgoing frame (assigning that
 * channel's next `seq` and writing the encoded frame is one atomic step) so bytes for a given
 * channel always reach the wire in the order their `seq` values were assigned. Flow control /
 * credit accounting (round-robining a stalled channel's frames against others) is E11-07's job,
 * not this issue's: every channel here has an unbounded inbound buffer.
 *
 * A peer's frame that fails [FrameDecoder] validation, or that violates the per-channel seq/ack
 * contract (D-57: `seq = 0`, a `seq` at or below that channel's current ack watermark, a duplicate
 * of an already-received above-watermark `seq`, or an `ack` above the highest `seq` this side has
 * itself sent on that channel), ends the reader loop and completes [closeReason] with
 * [MultiplexerClose.Violation] — this multiplexer never emits that frame, or any later one, to a
 * channel's [inbound] flow. No new [CloseCode] is needed for this: SPEC.md's D-57 grouping already
 * assigns the wire-defined `SEQ_REGRESSION` reason to the existing [CloseCode.MALFORMED_FRAME].
 * Once [closeReason] has completed, [send] throws [MultiplexerClosedException] instead of writing.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ChannelMultiplexer(
    private val source: FrameSource,
    private val sink: FrameSink,
) {
    private val writeLock = Mutex()

    private val outgoingSeq = ROUTABLE_CHANNELS.associateWithTo(mutableMapOf()) { 0L }
    private val incomingAck = ROUTABLE_CHANNELS.associateWithTo(mutableMapOf()) { 0L }
    private val pendingAboveWatermark = ROUTABLE_CHANNELS.associateWithTo(mutableMapOf()) { mutableSetOf<Long>() }

    private val inboundQueues: Map<Channel, KtChannel<InboundFrame>> =
        ROUTABLE_CHANNELS.associateWith { KtChannel(KtChannel.UNLIMITED) }

    private val closeResult = CompletableDeferred<MultiplexerClose>()

    /**
     * Completes once [start] stops, with why (SPEC.md #errors-and-close-codes, or a clean
     * [MultiplexerClose.PeerClosed]).
     */
    val closeReason: Deferred<MultiplexerClose> get() = closeResult

    /** Frames this multiplexer has routed for [channel] — never anything routed for a different channel. */
    fun inbound(channel: Channel): Flow<InboundFrame> = inboundQueues.getValue(channel).receiveAsFlow()

    /**
     * Builds and sends one frame on [channel]: [payload] sets the payload (and, for callers that
     * need it, nothing else — `channel`/`seq`/`ack` are always this multiplexer's own values,
     * applied after [payload] runs so a caller's lambda can never override them). Suspends only for
     * [FrameSink.write] itself (e.g. backpressure on the underlying connection).
     *
     * @throws MultiplexerClosedException if [closeReason] has already completed.
     */
    suspend fun send(
        channel: Channel,
        payload: EnvelopeKt.Dsl.() -> Unit,
    ) {
        require(channel in ROUTABLE_CHANNELS) { "cannot send on $channel" }
        writeLock.withLock {
            closeResult.let { if (it.isCompleted) throw MultiplexerClosedException(it.getCompleted()) }

            val seq = outgoingSeq.getValue(channel) + 1
            outgoingSeq[channel] = seq
            val ack = incomingAck.getValue(channel)
            val frame =
                envelope {
                    payload()
                    this.channel = channel
                    this.seq = seq
                    this.ack = ack
                }
            sink.write(FrameEncoder.encodeFrame(frame))
        }
    }

    /**
     * This multiplexer's single reader loop: decodes and routes frames from [source] until the
     * connection ends cleanly, [FrameDecoder] rejects one, reading fails, or a seq/ack violation is
     * detected — whichever happens first ends the loop and completes [closeReason] exactly once.
     */
    suspend fun start() {
        var close: MultiplexerClose? = null
        while (close == null) {
            val result =
                try {
                    FrameDecoder.decodeFrame(source)
                } catch (cause: IOException) {
                    close = MultiplexerClose.SourceFailed(cause)
                    continue
                }
            close = closeFor(result)
        }
        finish(close)
    }

    /** `null` means [result] was routed and the reader loop keeps going. */
    private suspend fun closeFor(result: DecodeResult): MultiplexerClose? =
        when (result) {
            is DecodeResult.Frame -> {
                val accepted = writeLock.withLock { acceptAndAdvanceAck(result.envelope) }
                if (accepted) {
                    routeToInbound(result.envelope)
                    null
                } else {
                    MultiplexerClose.Violation(CloseCode.MALFORMED_FRAME, MalformedFrameReason.SEQ_REGRESSION)
                }
            }

            is DecodeResult.Rejected -> {
                MultiplexerClose.Violation(result.closeCode, result.reason)
            }

            DecodeResult.EndOfStream -> {
                MultiplexerClose.PeerClosed
            }
        }

    private fun routeToInbound(envelope: Envelope) {
        val frame = InboundFrame(envelope.channel, envelope.seq, envelope.ack, envelope)
        inboundQueues.getValue(envelope.channel).trySend(frame)
    }

    /**
     * D-57's per-channel seq/ack contract. Caller holds [writeLock] (shared with [send], since this
     * reads the same per-channel outgoing-seq state that [send] mutates). Returns `false` — a
     * violation — without mutating any state, on any of: `seq = 0`; `seq` at or below this
     * channel's ack watermark; `seq` repeating an already-received above-watermark value; or `ack`
     * above the highest `seq` this side has itself sent on this channel.
     */
    private fun acceptAndAdvanceAck(envelope: Envelope): Boolean {
        val channel = envelope.channel
        val seq = envelope.seq
        val watermark = incomingAck.getValue(channel)
        val pending = pendingAboveWatermark.getValue(channel)

        val violatesSeq = seq == 0L || seq <= watermark || seq in pending
        val violatesAck = envelope.ack > outgoingSeq.getValue(channel)
        if (!violatesSeq && !violatesAck) {
            pending += seq
            var newWatermark = watermark
            while (pending.remove(newWatermark + 1)) {
                newWatermark += 1
            }
            incomingAck[channel] = newWatermark
        }
        return !violatesSeq && !violatesAck
    }

    private suspend fun finish(result: MultiplexerClose) {
        writeLock.withLock {
            if (closeResult.isCompleted) return
            inboundQueues.values.forEach { it.close() }
            closeResult.complete(result)
        }
    }

    private companion object {
        val ROUTABLE_CHANNELS: List<Channel> =
            listOf(
                Channel.CHANNEL_CONTROL,
                Channel.CHANNEL_NOTIFY,
                Channel.CHANNEL_CLIPBOARD,
                Channel.CHANNEL_FILES,
                Channel.CHANNEL_SMS,
                Channel.CHANNEL_CONTACTS,
                Channel.CHANNEL_CALLS,
                Channel.CHANNEL_INPUT,
                Channel.CHANNEL_STATUS,
            )
    }
}
