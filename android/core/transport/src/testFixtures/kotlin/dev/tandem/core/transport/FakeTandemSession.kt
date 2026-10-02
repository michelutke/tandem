package dev.tandem.core.transport

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * In-memory fake of [TandemSession] (E12-11): the seam every feature test uses instead of a real
 * [ByteStreamSession], so no feature unit test ever opens a socket. [send] records each call's
 * built [Envelope] onto [sentFrames], in order; [emitIncoming] and [emitState] let a test drive
 * this session's [receive] flows and [state] as if a peer, or the underlying transport, produced
 * them.
 */
class FakeTandemSession : TandemSession {
    private val mutableSentFrames = mutableListOf<Envelope>()

    /** Every [send] call so far, in order, as the [Envelope] it built. */
    val sentFrames: List<Envelope> get() = mutableSentFrames.toList()

    private val mutableState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected())
    override val state: StateFlow<ConnectionState> = mutableState.asStateFlow()

    private val inboundQueues = ConcurrentHashMap<Channel, KtChannel<Envelope>>()

    private var nextSendException: Exception? = null
    private var hangingSend = false
    private var closed = false

    override suspend fun send(
        channel: Channel,
        payload: EnvelopeKt.Dsl.() -> Unit,
    ) {
        nextSendException?.let {
            nextSendException = null
            throw it
        }

        if (hangingSend) {
            kotlinx.coroutines.awaitCancellation()
        }

        mutableSentFrames +=
            envelope {
                payload()
                this.channel = channel
            }
    }

    override fun receive(channel: Channel): Flow<Envelope> = queueFor(channel).receiveAsFlow()

    /** Emits [envelope] on [receive] for `envelope.channel`, as if a peer had sent it. */
    fun emitIncoming(envelope: Envelope) {
        queueFor(envelope.channel).trySend(envelope)
    }

    /** Sets [state] to [next], as if this session's underlying connection reached it. */
    fun emitState(next: ConnectionState) {
        mutableState.value = next
    }

    /** Configures the next [send] to throw [exception]. */
    fun failNextSend(exception: Exception) {
        nextSendException = exception
    }

    /** Configures [send] to hang indefinitely (used to test timeouts). */
    fun setHangingSend() {
        hangingSend = true
    }

    override fun close() {
        closed = true
        mutableState.value = ConnectionState.Disconnected()
        inboundQueues.values.forEach { it.close() }
    }

    private fun queueFor(channel: Channel): KtChannel<Envelope> =
        inboundQueues.getOrPut(channel) { KtChannel<Envelope>(KtChannel.UNLIMITED).also { if (closed) it.close() } }
}
