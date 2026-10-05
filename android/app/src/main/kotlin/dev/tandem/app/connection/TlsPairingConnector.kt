package dev.tandem.app.connection

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.pairing.PairingConnection
import dev.tandem.core.pairing.PairingConnector
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.tls.SslClientFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.InetAddress
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.time.Clock
import javax.net.ssl.SSLPeerUnverifiedException
import javax.net.ssl.X509KeyManager

/**
 * Production [PairingConnector] (E20-26, invariants 1, 3, 5): dials the invite's Mac over mTLS with
 * a [PinningTrustManager] pinned to [PinSource] (the QR fingerprint, never the trust store), so no
 * [ByteStreamSession] -- and no application byte -- exists for a peer that fails the pin check. A
 * session that does not reach Ready (version mismatch, hello failure) is closed and fails closed.
 * Never listens (invariant 4).
 */
class TlsPairingConnector internal constructor(
    private val keyManager: X509KeyManager,
    private val clock: Clock,
    private val ioDispatcher: CoroutineDispatcher,
    private val sessionDispatcher: CoroutineDispatcher,
    private val dialer: PairingSocketDialer,
) : PairingConnector {
    constructor(
        keyManager: X509KeyManager,
        clock: Clock,
        ioDispatcher: CoroutineDispatcher,
        sessionDispatcher: CoroutineDispatcher,
    ) : this(keyManager, clock, ioDispatcher, sessionDispatcher, TlsPairingSocketDialer(keyManager))

    override suspend fun connect(
        address: String,
        port: Int,
        pinSource: PinSource,
    ): PairingConnection {
        var opened: ByteStream? = null
        val (stream, macSpkiDer) =
            try {
                withContext(ioDispatcher) {
                    dialer.dial(address, port, pinSource).also { opened = it.first }
                }
            } catch (e: CancellationException) {
                opened?.close()
                throw e
            } catch (e: IOException) {
                if (generateSequence<Throwable>(e) { it.cause }.any { it is CertificateException }) {
                    throw CertificateException("pinned peer mismatch")
                }
                throw e
            }
        val session = ByteStreamSession(stream, clock, sessionDispatcher)
        try {
            val outcome = session.state.first { it is ConnectionState.Ready || it is ConnectionState.Failed }
            if (outcome is ConnectionState.Failed) throw IOException("pairing connection failed")
        } catch (e: CancellationException) {
            session.close()
            throw e
        } catch (e: IOException) {
            session.close()
            throw e
        }
        val phoneCertificate = keyManager.getCertificateChain(null).first() as X509Certificate
        return PairingConnection(session, macSpkiDer, phoneCertificate.publicKey.encoded)
    }
}

/** Blocking mTLS dial: the handshaked stream plus the peer leaf's SPKI DER. */
internal fun interface PairingSocketDialer {
    fun dial(
        address: String,
        port: Int,
        pinSource: PinSource,
    ): Pair<ByteStream, ByteArray>
}

internal class TlsPairingSocketDialer(
    private val keyManager: X509KeyManager,
) : PairingSocketDialer {
    override fun dial(
        address: String,
        port: Int,
        pinSource: PinSource,
    ): Pair<ByteStream, ByteArray> {
        val factory = SslClientFactory(keyManager, PinningTrustManager(pinSource))
        val socket = factory.createSocket()
        val stream = factory.connect(socket, InetAddress.getByName(address), port)
        return try {
            stream to
                socket.session.peerCertificates
                    .first()
                    .publicKey.encoded
        } catch (e: SSLPeerUnverifiedException) {
            stream.close()
            throw IOException("peer certificate unavailable", e)
        }
    }
}
