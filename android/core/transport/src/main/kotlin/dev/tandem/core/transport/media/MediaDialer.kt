package dev.tandem.core.transport.media

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.mediaHello
import dev.tandem.protocol.v1.requestMediaTicket
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.IOException
import java.nio.ByteBuffer
import java.security.cert.CertificateException
import javax.net.ssl.SSLHandshakeException

/** Outcome of [MediaDialer.dial]. */
sealed class MediaDialResult {
    /** The pinned mTLS handshake completed and `MediaHello` was sent as the first frame. */
    class Connected(
        val stream: ByteStream,
    ) : MediaDialResult()

    /** The peer's SPKI fingerprint did not match the control session's pin; zero application bytes were sent. */
    data object PinMismatch : MediaDialResult()

    /** No `MediaTicketGrant` arrived in time, so no media connection was attempted. */
    data object TicketUnavailable : MediaDialResult()

    /** The ticket's own 30 s deadline (requester's monotonic clock) passed before the dial; nothing was dialed. */
    data object TicketExpired : MediaDialResult()

    /** The media connection could not be established or `MediaHello` could not be written. */
    data object Unreachable : MediaDialResult()
}

/**
 * Requests a `MediaTicketGrant` over the control [session] and opens the second mTLS connection to
 * the same pinned peer, sending `MediaHello { ticket }` as its first frame (E60-02; SPEC.md
 * #media-ticket). [pinSource] MUST be the pin source the control connection trusts: it is handed to
 * [streamFactory] unchanged, so the media dial is authenticated against the same pinned SPKI before
 * `MediaHello` is written (invariants 1, 3, 5). The ticket is never logged (invariant 7).
 */
class MediaDialer(
    private val session: TandemSession,
    private val streamFactory: MediaStreamFactory,
    private val pinSource: PinSource,
    private val elapsedRealtime: ElapsedRealtimeSource,
    private val ioDispatcher: CoroutineDispatcher,
    private val grantTimeoutMillis: Long = GRANT_TIMEOUT_MILLIS,
) {
    private val ticketLock = Mutex()
    private var unansweredRequests = 0

    suspend fun dial(address: CandidateAddress): MediaDialResult {
        val issued = requestTicket() ?: return MediaDialResult.TicketUnavailable
        val caller = currentCoroutineContext().job
        return withContext(ioDispatcher) {
            connectAndSendHello(address, issued).also {
                if (it is MediaDialResult.Connected && !caller.isActive) it.stream.closeAbruptly()
            }
        }
    }

    /**
     * `MediaTicketGrant` carries no request id, so grants are matched to requests by order: every
     * request that timed out or failed to send may still be answered late, and the next dial discards
     * that many grants before taking its own.
     */
    private suspend fun requestTicket(): IssuedTicket? =
        ticketLock.withLock {
            try {
                withTimeout(grantTimeoutMillis) {
                    coroutineScope {
                        val staleGrants = unansweredRequests
                        val pending =
                            async(start = CoroutineStart.UNDISPATCHED) {
                                val grant =
                                    session
                                        .receive(Channel.CHANNEL_CONTROL)
                                        .filter { it.hasMediaTicketGrant() }
                                        .drop(staleGrants)
                                        .first()
                                        .mediaTicketGrant
                                IssuedTicket(
                                    grant.ticket,
                                    elapsedRealtime.elapsedRealtimeMillis() + TICKET_VALIDITY_MILLIS,
                                )
                            }
                        unansweredRequests = staleGrants + 1
                        session.send(Channel.CHANNEL_CONTROL) { requestMediaTicket = requestMediaTicket { } }
                        pending.await().also { unansweredRequests = 0 }
                    }
                }
            } catch (_: TimeoutCancellationException) {
                null
            } catch (_: IOException) {
                null
            }
        }

    private fun connectAndSendHello(
        address: CandidateAddress,
        issued: IssuedTicket,
    ): MediaDialResult =
        if (elapsedRealtime.elapsedRealtimeMillis() >= issued.deadlineMillis) {
            MediaDialResult.TicketExpired
        } else {
            try {
                sendHello(streamFactory.open(address, pinSource), issued)
            } catch (e: SSLHandshakeException) {
                if (e.hasCertificateCause()) MediaDialResult.PinMismatch else MediaDialResult.Unreachable
            } catch (_: IOException) {
                MediaDialResult.Unreachable
            }
        }

    private fun sendHello(
        stream: ByteStream,
        issued: IssuedTicket,
    ): MediaDialResult =
        try {
            stream.output.write(encodeMediaHelloFrame(issued.ticket))
            stream.output.flush()
            MediaDialResult.Connected(stream)
        } catch (_: IOException) {
            stream.closeAbruptly()
            MediaDialResult.Unreachable
        }

    private fun encodeMediaHelloFrame(ticket: ByteString): ByteArray {
        val body = mediaHello { this.ticket = ticket }.toByteArray()
        return ByteBuffer
            .allocate(LENGTH_PREFIX_BYTES + body.size)
            .putInt(body.size)
            .put(body)
            .array()
    }

    private fun Throwable.hasCertificateCause(): Boolean =
        generateSequence(this) { it.cause }.any { it is CertificateException }

    private class IssuedTicket(
        val ticket: ByteString,
        val deadlineMillis: Long,
    )

    private companion object {
        /** SPEC.md #media-ticket: the requester's own deadline is receipt of the grant plus 30 s. */
        const val TICKET_VALIDITY_MILLIS = 30_000L

        const val GRANT_TIMEOUT_MILLIS = 5_000L
        const val LENGTH_PREFIX_BYTES = 4
    }
}
