package dev.tandem.app.connection

import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.crypto.SpkiFingerprintException
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.pairing.IdentityUnavailableException
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.HeartbeatDependencies
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.tls.SslClientFactory
import dev.tandem.core.transport.tls.SslSocketByteStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.InetAddress
import java.security.cert.CertificateException
import java.time.Clock
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.X509KeyManager

sealed interface DialResult {
    data class Connected(
        val session: TandemSession,
        val peer: SpkiFingerprint,
        val peerSpkiDer: ByteArray? = null,
        val address: CandidateAddress? = null,
    ) : DialResult

    data class PinMismatch(
        val failure: ConnectionFailure,
    ) : DialResult

    data class Unreachable(
        val failure: ConnectionFailure?,
    ) : DialResult
}

fun interface SessionDialer {
    suspend fun dial(candidate: CandidateAddress): DialResult
}

/**
 * Dials [candidate] over mTLS (E20-23, invariants 1, 3, 5): the trust manager accepts only the SPKI
 * fingerprints [pinnedFingerprints] returns at dial time (primary, grace and pending pins), so no
 * [ByteStreamSession] -- and therefore no application byte -- exists for a peer that failed the pin
 * check. Never listens (invariant 4).
 */
@Suppress("LongParameterList") // dial seams: keys, identity, pins, clock, two dispatchers, heartbeat
class TlsSessionDialer(
    private val keyManager: X509KeyManager,
    private val identity: IdentityBootstrap,
    private val pinnedFingerprints: suspend () -> List<SpkiFingerprint>,
    private val wasPreviouslyPinned: (SpkiFingerprint) -> Boolean,
    private val clock: Clock,
    private val ioDispatcher: CoroutineDispatcher,
    private val sessionDispatcher: CoroutineDispatcher,
    private val heartbeatDependencies: HeartbeatDependencies?,
) : SessionDialer {
    override suspend fun dial(candidate: CandidateAddress): DialResult {
        val pins = pinnedFingerprints()
        if (pins.isEmpty() || !identityReady()) return DialResult.Unreachable(null)
        val factory = SslClientFactory(keyManager, PinningTrustManager { pins })
        var opened: SslSocketByteStream? = null
        return try {
            val (stream, peerSpkiDer) =
                withContext(ioDispatcher) {
                    val socket = factory.createSocket()
                    val stream = factory.connect(socket, InetAddress.getByName(candidate.host), candidate.port)
                    opened = stream
                    try {
                        val der =
                            socket.session.peerCertificates
                                .first()
                                .publicKey.encoded
                        spkiFingerprint(der)
                        stream to der
                    } catch (e: SpkiFingerprintException) {
                        stream.close()
                        throw IOException("peer key is not pinnable", e)
                    }
                }
            DialResult.Connected(
                ByteStreamSession(stream, clock, sessionDispatcher, heartbeatDependencies),
                spkiFingerprint(peerSpkiDer),
                peerSpkiDer,
                candidate,
            )
        } catch (e: CancellationException) {
            opened?.close()
            throw e
        } catch (e: IOException) {
            classifyDialFailure(e, pins.any(wasPreviouslyPinned))
        }
    }

    private suspend fun identityReady(): Boolean =
        try {
            identity.ensure()
            true
        } catch (expectedIdentityFailure: IdentityUnavailableException) {
            false
        }
}

/**
 * Maps a dial [error] to a sanitized failure (invariant 7: no message text escapes). A
 * [CertificateException] anywhere in the cause chain is the pinning trust manager rejecting the
 * peer; other TLS handshake failures go through [ConnectionFailureClassifier] (REVOKED) and
 * otherwise surface as a generic handshake failure. Non-TLS errors are plain unreachability.
 */
internal fun classifyDialFailure(
    error: IOException,
    wasPreviouslyPinned: Boolean,
): DialResult {
    val chain = generateSequence<Throwable>(error) { it.cause }.toList()
    return when {
        chain.any { it is CertificateException } -> {
            DialResult.PinMismatch(ConnectionFailure.HandshakeError(PIN_MISMATCH))
        }

        chain.none { it is SSLHandshakeException } -> {
            DialResult.Unreachable(null)
        }

        else -> {
            DialResult.Unreachable(classifyHandshake(chain, wasPreviouslyPinned))
        }
    }
}

private fun classifyHandshake(
    chain: List<Throwable>,
    wasPreviouslyPinned: Boolean,
): ConnectionFailure {
    val raw = ConnectionFailure.HandshakeError(chain.joinToString(" ") { it.message.orEmpty() })
    val classified = ConnectionFailureClassifier.classify(raw, wasPreviouslyPinned)
    return if (classified === raw) ConnectionFailure.HandshakeError(HANDSHAKE_FAILED) else classified
}

private const val PIN_MISMATCH = "PIN_MISMATCH"
private const val HANDSHAKE_FAILED = "HANDSHAKE_FAILED"
