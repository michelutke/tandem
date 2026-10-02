package dev.tandem.core.protocol.multiplex

import dev.tandem.core.protocol.CloseCode
import dev.tandem.core.protocol.DecodeResult
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.core.protocol.FrameSink
import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.protocol.MalformedFrameReason
import dev.tandem.core.protocol.flowcontrol.CreditCaps
import dev.tandem.core.protocol.flowcontrol.CreditLedger
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.CreditGrant
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.creditGrant
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.IOException
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * Channel multiplexer (E11-05, flow control added E11-07; aligned with the macOS twin, E11-06 /
 * E11-08): routes decoded [Envelope]s to per-channel inbound sinks, assigns outgoing `seq`/`ack`
 * per SPEC.md #framing-and-envelope (`docs/planning/decisions.md` D-57), and enforces the
 * per-channel credit-based flow control of SPEC.md #channels-and-flow-control-credits (D-64) on
 * top of [CreditLedger]'s pure accounting ([flowControl]). Reads through [FrameSource] and writes
 * through [FrameSink] rather than `core/transport`'s `ByteStream` directly (this module has no
 * dependency on `core/transport`, mirroring [FrameDecoder]/[FrameEncoder]).
 *
 * Structured concurrency: [start] launches this multiplexer's single reader loop and its single
 * fair outbound writer loop ([writer]) together — callers launch [start] once, in whichever
 * scope/dispatcher owns the underlying connection (this class never picks its own dispatcher, so
 * it never needs one injected) — and cancels the writer once the reader loop ends. [send] may be
 * called concurrently from any number of coroutines: it suspends until that channel has
 * outstanding send credit (feature channels only; `CONTROL` is exempt, SPEC.md "CONTROL is exempt
 * from credit accounting"), then atomically assigns that channel's next `seq` and enqueues the
 * frame onto a per-channel outbound queue — it does not itself write to [sink]. The writer loop
 * round-robins across every channel with a queued frame, draining at most one frame per channel
 * per pass, so a newly queued frame on one channel waits behind at most one frame already queued
 * on every other channel (SPEC.md: "a large FILES transfer cannot delay a NOTIFY frame").
 *
 * A peer's frame that fails [FrameDecoder] validation, or that violates the per-channel seq/ack
 * contract (D-57: `seq = 0`, a `seq` at or below that channel's current ack watermark, a duplicate
 * of an already-received above-watermark `seq`, or an `ack` above the highest `seq` this side has
 * itself sent on that channel), ends the reader loop and completes [closeReason] with
 * [MultiplexerClose.Violation] — this multiplexer never emits that frame, or any later one, to a
 * channel's [inbound] flow. No new [CloseCode] is needed for this: SPEC.md's D-57 grouping already
 * assigns the wire-defined `SEQ_REGRESSION` reason to the existing [CloseCode.MALFORMED_FRAME]. A
 * peer frame on a feature channel sent past the credit this side granted it, or a peer
 * `CreditGrant` that would take this side's own send balance above its cap, instead completes
 * [closeReason] with [MultiplexerClose.CreditViolation] (SPEC.md, D-64). Once [closeReason] has
 * completed, [send] throws [MultiplexerClosedException] instead of enqueuing.
 *
 * Receive-side replenishment: [inbound] wraps each feature channel's flow so that once a frame is
 * actually taken out of that channel's inbound queue (SPEC.md: "only once the channel's
 * application-level consumer has actually taken the corresponding frame out of the... buffer, not
 * merely once the frame has been decoded off the wire"), this side's cumulative consumption count
 * for that channel is checked against half its cap; crossing that threshold sends exactly one
 * `CreditGrant` restoring the peer's granted balance to the channel's cap, and re-arms the trigger.
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
    private val outboundQueues: Map<Channel, KtChannel<Envelope>> =
        ROUTABLE_CHANNELS.associateWith { KtChannel(KtChannel.UNLIMITED) }

    private val flowControl = FlowControl()
    private val writer = Writer()

    private val closeResult = CompletableDeferred<MultiplexerClose>()

    /**
     * Completes once [start] stops, with why (SPEC.md #errors-and-close-codes, or a clean
     * [MultiplexerClose.PeerClosed]).
     */
    val closeReason: Deferred<MultiplexerClose> get() = closeResult

    private val mutableSent = MutableSharedFlow<Unit>(extraBufferCapacity = SIGNAL_BUFFER_CAPACITY)

    /**
     * Fires once for every frame this multiplexer actually writes to [sink], on any channel
     * (E20-15; SPEC.md #heartbeat: "any frame it sends" resets the unsolicited-heartbeat idle-send
     * timer; aligned with the macOS twin's `ChannelMultiplexer.sent`, E20-05).
     */
    val sent: SharedFlow<Unit> = mutableSent.asSharedFlow()

    private val mutableReceived = MutableSharedFlow<FrameArrival>(extraBufferCapacity = SIGNAL_BUFFER_CAPACITY)

    /**
     * Fires once for every frame this multiplexer accepts off the wire, on any channel, at the
     * moment it clears D-57's seq/ack contract -- before its credit-related outcome is even
     * considered, and regardless of whether any caller ever collects it off [inbound] (E20-15;
     * SPEC.md #heartbeat: "any frame" received resets the dead-peer timer; aligned with the macOS
     * twin's `ChannelMultiplexer.received`, E20-05). Never consumes [inbound] itself, so observing
     * this never drops a frame another consumer would otherwise see.
     */
    val received: SharedFlow<FrameArrival> = mutableReceived.asSharedFlow()

    /**
     * Frames this multiplexer has routed for [channel] — never anything routed for a different
     * channel. For a feature channel, collecting an item from this flow is this side's
     * application-level consumption event (SPEC.md D-64): it counts toward that channel's
     * replenishment trigger and may cause a `CreditGrant` to be sent.
     */
    fun inbound(channel: Channel): Flow<InboundFrame> {
        val frames = inboundQueues.getValue(channel).receiveAsFlow()
        return if (channel in FEATURE_CHANNELS) frames.onEach { flowControl.onConsumed(channel) } else frames
    }

    /**
     * Builds and sends one frame on [channel]: [payload] sets the payload (and, for callers that
     * need it, nothing else — `channel`/`seq`/`ack` are always this multiplexer's own values,
     * applied after [payload] runs so a caller's lambda can never override them). Suspends until
     * [channel] has outstanding send credit (feature channels only, SPEC.md D-64) and then only to
     * enqueue the frame onto its per-channel outbound queue — actually writing it to [sink] is
     * [writer]'s job, not this call's.
     *
     * @throws MultiplexerClosedException if [closeReason] has already completed.
     */
    suspend fun send(
        channel: Channel,
        payload: EnvelopeKt.Dsl.() -> Unit,
    ) {
        require(channel in ROUTABLE_CHANNELS) { "cannot send on $channel" }
        throwIfClosed()
        if (channel in FEATURE_CHANNELS) {
            flowControl.awaitSendCredit(channel)
        }
        writeLock.withLock {
            throwIfClosed()
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
            outboundQueues.getValue(channel).trySend(frame)
        }
    }

    private fun throwIfClosed() {
        closeResult.let { if (it.isCompleted) throw MultiplexerClosedException(it.getCompleted()) }
    }

    /**
     * This multiplexer's single reader loop and single fair writer loop ([writer]): reads and
     * routes frames from [source] until the connection ends cleanly, [FrameDecoder] rejects one,
     * reading fails, or a seq/ack or flow-control violation is detected — whichever happens first
     * ends the reader loop, cancels the writer loop, and completes [closeReason] exactly once.
     */
    suspend fun start() =
        coroutineScope {
            val writerJob = launch { writer.run() }
            readLoop()
            writerJob.cancel()
        }

    private suspend fun readLoop() {
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

    /**
     * `null` means [result] was routed and the reader loop keeps going. A well-formed [DecodeResult.Frame]
     * still has to clear D-57's seq/ack contract before its credit-related outcome (SPEC.md D-64,
     * [creditOutcomeFor]) is even considered.
     */
    private suspend fun closeFor(result: DecodeResult): MultiplexerClose? =
        when (result) {
            is DecodeResult.Frame -> {
                val violation = writeLock.withLock { acceptAndAdvanceAck(result.envelope) }
                if (violation != null) {
                    MultiplexerClose.Violation(CloseCode.MALFORMED_FRAME, violation)
                } else {
                    mutableReceived.tryEmit(
                        FrameArrival(
                            channel = result.envelope.channel,
                            isHeartbeat = result.envelope.payloadCase == Envelope.PayloadCase.HEARTBEAT,
                        ),
                    )
                    creditOutcomeFor(result.envelope)
                }
            }

            is DecodeResult.Rejected -> {
                MultiplexerClose.Violation(result.closeCode, result.reason)
            }

            DecodeResult.EndOfStream -> {
                MultiplexerClose.PeerClosed
            }
        }

    /**
     * The credit-related outcome of routing [envelope] (SPEC.md D-64): applies an incoming
     * `CreditGrant`, checks a feature-channel frame's arrival against the credit this side granted
     * the peer, or (neither applies) simply routes it to [inbound] — always returning `null` unless
     * that check reports [MultiplexerClose.CreditViolation].
     */
    private suspend fun creditOutcomeFor(envelope: Envelope): MultiplexerClose? {
        val isIncomingGrant =
            envelope.channel == Channel.CHANNEL_CONTROL && envelope.payloadCase == Envelope.PayloadCase.CREDIT_GRANT
        if (isIncomingGrant) {
            return flowControl.applyIncomingGrant(envelope.creditGrant)
        }
        val creditViolation =
            if (envelope.channel in FEATURE_CHANNELS) flowControl.acceptArrival(envelope.channel) else null
        if (creditViolation == null) routeToInbound(envelope)
        return creditViolation
    }

    private fun routeToInbound(envelope: Envelope) {
        val frame = InboundFrame(envelope.channel, envelope.seq, envelope.ack, envelope)
        inboundQueues.getValue(envelope.channel).trySend(frame)
    }

    /**
     * D-57's per-channel seq/ack contract. Caller holds [writeLock] (shared with [send], since this
     * reads the same per-channel outgoing-seq state that [send] mutates). Returns the violation
     * reason — without mutating any state — on any of: `seq = 0`; `seq` at or below this channel's
     * ack watermark; `seq` repeating an already-received above-watermark value; `ack` above the
     * highest `seq` this side has itself sent on this channel; or the channel's above-watermark
     * pending set already holding [CreditCaps.PROTOCOL_MAX] entries (D-64: a legitimate,
     * credit-bound peer can never make this many `seq` values pending at once). Returns `null` on
     * success.
     */
    private fun acceptAndAdvanceAck(envelope: Envelope): MalformedFrameReason? {
        val channel = envelope.channel
        val seq = envelope.seq
        val watermark = incomingAck.getValue(channel)
        val pending = pendingAboveWatermark.getValue(channel)

        val violatesSeq = seq == 0L || seq <= watermark || seq in pending
        val violatesAck = envelope.ack > outgoingSeq.getValue(channel)
        val violation =
            when {
                violatesSeq || violatesAck -> MalformedFrameReason.SEQ_REGRESSION
                pending.size >= CreditCaps.PROTOCOL_MAX -> MalformedFrameReason.SEQ_GAP_TOO_LARGE
                else -> null
            }
        if (violation == null) {
            pending += seq
            var newWatermark = watermark
            while (pending.remove(newWatermark + 1)) {
                newWatermark += 1
            }
            incomingAck[channel] = newWatermark
        }
        return violation
    }

    private suspend fun finish(result: MultiplexerClose) {
        writeLock.withLock {
            if (closeResult.isCompleted) return
            inboundQueues.values.forEach { it.close() }
            closeResult.complete(result)
        }
        flowControl.failWaiters(result)
    }

    /**
     * This multiplexer's single fair writer loop (E11-07): round-robins across every channel with
     * a queued outbound frame, writing at most one frame per channel per pass, so a channel that
     * keeps producing frames can never fully starve another (E11-09 covers sustained-contention
     * guarantees; this is the round-robin mechanism itself).
     *
     * Once [closeResult] has completed, this loop stops writing anything: it never relies on
     * [start]'s `writerJob.cancel()` alone, since Kotlin cancellation only takes effect at a
     * suspension point and a frame already popped off a channel's outbound queue would otherwise
     * still reach [sink] (mirroring the macOS twin's `drainLoop`/`finish`). A write already in
     * flight when [closeResult] completes is unaffected — it already committed to going out —
     * but every frame popped afterward is discarded by [failQueued] instead of written.
     */
    private inner class Writer {
        suspend fun run() {
            try {
                var startIndex = 0
                while (!closeResult.isCompleted) {
                    val nextIndex = drainOnePass(startIndex)
                    startIndex = nextIndex ?: awaitAndWriteAny() ?: continue
                }
            } catch (cause: IOException) {
                finish(MultiplexerClose.SourceFailed(cause))
            }
            failQueued()
        }

        /** Writes at most one frame per channel, starting at [startIndex]; `null` if nothing was queued. */
        private suspend fun drainOnePass(startIndex: Int): Int? {
            for (offset in ROUTABLE_CHANNELS.indices) {
                val index = (startIndex + offset) % ROUTABLE_CHANNELS.size
                val result = outboundQueues.getValue(ROUTABLE_CHANNELS[index]).tryReceive()
                if (result.isSuccess) {
                    sink.write(FrameEncoder.encodeFrame(result.getOrThrow()))
                    mutableSent.tryEmit(Unit)
                    return (index + 1) % ROUTABLE_CHANNELS.size
                }
            }
            return null
        }

        /**
         * Suspends until any channel's outbound queue has a frame, writes it, and returns the next
         * start index — or `null` once [closeResult] completes first, so this never suspends
         * forever waiting for a frame [send] will no longer enqueue.
         */
        private suspend fun awaitAndWriteAny(): Int? {
            val index =
                select {
                    closeResult.onAwait { CLOSED_INDEX }
                    for (channel in ROUTABLE_CHANNELS) {
                        outboundQueues.getValue(channel).onReceive { frame ->
                            sink.write(FrameEncoder.encodeFrame(frame))
                            mutableSent.tryEmit(Unit)
                            ROUTABLE_CHANNELS.indexOf(channel)
                        }
                    }
                }
            return if (index == CLOSED_INDEX) null else (index + 1) % ROUTABLE_CHANNELS.size
        }

        /**
         * Pops and discards every frame still sitting in every channel's outbound queue once
         * [closeResult] has completed: SPEC.md/security invariant 1 — no frame reaches [sink]
         * after this multiplexer has closed, so a queued backlog is failed rather than written.
         */
        private fun failQueued() {
            for (channel in ROUTABLE_CHANNELS) {
                while (outboundQueues.getValue(channel).tryReceive().isSuccess) {
                    // Popped after close: never written to sink (MultiplexerClosedException is
                    // what a concurrent send() caller already observes; there is no per-frame
                    // continuation here to fail explicitly).
                }
            }
        }
    }

    /**
     * This multiplexer's credit-based flow control (SPEC.md #channels-and-flow-control-credits,
     * D-64), built on [CreditLedger]'s pure accounting: [sendCredit] is this side's own outstanding
     * balance per feature channel (gates [send]), and [receiveCredit] is this side's bookkeeping of
     * what it has granted its peer per feature channel (gates a peer frame's arrival, and drives
     * this side's own `CreditGrant` issuance as frames are consumed). `CONTROL` carries neither.
     */
    private inner class FlowControl {
        private val sendCredit: Map<Channel, SendCredit> =
            FEATURE_CHANNELS.associateWith { SendCredit(CreditCaps.capFor(it)) }
        private val receiveCredit: Map<Channel, ReceiveCredit> =
            FEATURE_CHANNELS.associateWith { ReceiveCredit(CreditCaps.capFor(it)) }

        /**
         * Suspends until [channel] (a feature channel) has at least 1 credit, then consumes it.
         * Racing this against [applyIncomingGrant] (both take [SendCredit.mutex]) is what makes
         * "insufficient credit right now" and "register to be woken by the next grant" atomic: a
         * grant arriving between this check and registering a waiter can never be missed.
         */
        suspend fun awaitSendCredit(channel: Channel) {
            val credit = sendCredit.getValue(channel)
            while (true) {
                val waiter =
                    credit.mutex.withLock {
                        if (credit.ledger.consume(1) is CreditLedger.ConsumeResult.Ok) {
                            null
                        } else {
                            CompletableDeferred<Unit>().also { credit.waiters += it }
                        }
                    }
                if (waiter == null) return
                waiter.await()
            }
        }

        /**
         * This side's application-level consumption event for [channel] (a feature channel,
         * SPEC.md D-64): counts toward the replenishment trigger, sending exactly one `CreditGrant`
         * once cumulative consumption since the last grant first crosses half of [channel]'s cap.
         */
        suspend fun onConsumed(channel: Channel) {
            val credit = receiveCredit.getValue(channel)
            val grantAmount =
                credit.mutex.withLock {
                    credit.consumedSinceGrant += 1
                    if (credit.consumedSinceGrant >= credit.cap / 2) {
                        val amount = credit.cap - credit.ledger.balance
                        credit.ledger.applyGrant(amount)
                        credit.consumedSinceGrant = 0
                        amount
                    } else {
                        0
                    }
                }
            if (grantAmount > 0) {
                sendCreditGrant(channel, grantAmount)
            }
        }

        private suspend fun sendCreditGrant(
            channel: Channel,
            amount: Int,
        ) {
            // Captured into distinctly named locals before entering the DSL lambdas below: both
            // EnvelopeKt.Dsl and CreditGrantKt.Dsl declare their own `channel` property, which
            // would otherwise shadow this function's parameters.
            val grantChannel = channel
            val grantAmount = amount
            send(Channel.CHANNEL_CONTROL) {
                creditGrant =
                    creditGrant {
                        this.channel = grantChannel
                        this.amount = grantAmount
                    }
            }
        }

        /** SPEC.md D-64 "Violation": a peer frame on [channel] past the credit this side granted it. */
        suspend fun acceptArrival(channel: Channel): MultiplexerClose? {
            val credit = receiveCredit.getValue(channel)
            val insufficient =
                credit.mutex.withLock {
                    credit.ledger.consume(1) is CreditLedger.ConsumeResult.Insufficient
                }
            return if (insufficient) MultiplexerClose.CreditViolation(channel) else null
        }

        /**
         * SPEC.md D-64: applies a peer `CreditGrant` to this side's own send balance. `amount == 0`
         * is a well-formed no-op. A grant naming a channel this side does not track credit for
         * (`CONTROL`, `CHANNEL_UNSPECIFIED`, or unrecognized) never names a real credit ledger and
         * closes with [CloseCode.MALFORMED_FRAME]/[MalformedFrameReason.UNKNOWN_CHANNEL] (SPEC.md
         * #channels-and-flow-control-credits), matching the macOS twin's
         * `applyIncomingCreditGrant`.
         */
        suspend fun applyIncomingGrant(grant: CreditGrant): MultiplexerClose? {
            val credit =
                sendCredit[grant.channel]
                    ?: return MultiplexerClose.Violation(
                        CloseCode.MALFORMED_FRAME,
                        MalformedFrameReason.UNKNOWN_CHANNEL,
                    )
            val overflow =
                grant.amount > 0 &&
                    credit.mutex.withLock {
                        when (credit.ledger.applyGrant(grant.amount)) {
                            is CreditLedger.GrantResult.Ok -> {
                                val waiters = credit.waiters.toList()
                                credit.waiters.clear()
                                waiters.forEach { it.complete(Unit) }
                                false
                            }

                            CreditLedger.GrantResult.Overflow -> {
                                true
                            }
                        }
                    }
            return if (overflow) MultiplexerClose.CreditViolation(grant.channel) else null
        }

        /**
         * Wakes every [SendCredit.waiters] entry across every feature channel with
         * [MultiplexerClosedException], so an [awaitSendCredit] caller currently suspended throws
         * instead of hanging forever now that this multiplexer has closed (mirrors the macOS
         * twin's `finish()` kicking the drain loop so every pending continuation resolves).
         */
        suspend fun failWaiters(close: MultiplexerClose) {
            for (credit in sendCredit.values) {
                val waiters =
                    credit.mutex.withLock {
                        val current = credit.waiters.toList()
                        credit.waiters.clear()
                        current
                    }
                waiters.forEach { it.completeExceptionally(MultiplexerClosedException(close)) }
            }
        }
    }

    /**
     * One feature channel's outgoing send-credit state (SPEC.md D-64), guarded by [mutex]:
     * [ledger] is this side's own remaining balance, and [waiters] are
     * [FlowControl.awaitSendCredit] callers currently suspended because it was empty, woken once
     * [FlowControl.applyIncomingGrant] restores it.
     */
    private class SendCredit(
        cap: Int,
    ) {
        val mutex = Mutex()
        val ledger = CreditLedger(cap)
        val waiters = mutableListOf<CompletableDeferred<Unit>>()
    }

    /**
     * One feature channel's granted-to-peer credit state (SPEC.md D-64), guarded by [mutex]:
     * [ledger] mirrors the peer's remaining balance from this side's own bookkeeping (decremented
     * on arrival, restored when this side sends a `CreditGrant`), and [consumedSinceGrant] is the
     * separate cumulative-consumption counter that drives the replenishment trigger.
     */
    private class ReceiveCredit(
        val cap: Int,
    ) {
        val mutex = Mutex()
        val ledger = CreditLedger(cap)
        var consumedSinceGrant = 0
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
                Channel.CHANNEL_MEDIA_CONTROL,
            )

        /** [ROUTABLE_CHANNELS] minus `CONTROL`, which is exempt from credit accounting (SPEC.md D-64). */
        val FEATURE_CHANNELS: List<Channel> = ROUTABLE_CHANNELS.filter { it != Channel.CHANNEL_CONTROL }

        /** [Writer.awaitAndWriteAny]'s sentinel return value for "[closeResult] completed first". */
        const val CLOSED_INDEX = -1

        /** [sent]/[received]'s replay-less buffer: generous enough that a slow collector never blocks the hot path. */
        const val SIGNAL_BUFFER_CAPACITY = 64
    }
}
