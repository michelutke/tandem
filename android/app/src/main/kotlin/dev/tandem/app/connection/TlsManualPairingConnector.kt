package dev.tandem.app.connection

import dev.tandem.core.crypto.UnpinnedPeerTrustManager
import dev.tandem.core.pairing.ManualPairingConnector
import dev.tandem.core.pairing.PairingConnection
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.tls.SslClientFactory
import kotlinx.coroutines.CoroutineDispatcher
import java.io.IOException
import java.net.InetAddress
import java.time.Clock
import javax.net.ssl.SSLPeerUnverifiedException
import javax.net.ssl.X509KeyManager

/**
 * Production [ManualPairingConnector] (E73-03, ADR-008, invariants 3, 4, 5): dials the typed Mac
 * over mTLS without a pin, because manual pairing has no QR fingerprint. The handshake still proves
 * the peer holds the key it presents (`CertificateVerify`) and a non-P-256 key fails closed
 * ([UnpinnedPeerTrustManager]), but only the SAS comparison authenticates the peer, and the Mac is
 * pinned later, only by the state machine after the owner confirms. Nothing but pairing messages
 * is ever sent on the returned connection. Never listens (invariant 4).
 */
class TlsManualPairingConnector internal constructor(
    private val keyManager: X509KeyManager,
    private val clock: Clock,
    private val ioDispatcher: CoroutineDispatcher,
    private val sessionDispatcher: CoroutineDispatcher,
    private val identity: IdentityBootstrap,
    private val dialer: ManualSocketDialer,
) : ManualPairingConnector {
    constructor(
        keyManager: X509KeyManager,
        clock: Clock,
        ioDispatcher: CoroutineDispatcher,
        sessionDispatcher: CoroutineDispatcher,
        identity: IdentityBootstrap,
    ) : this(keyManager, clock, ioDispatcher, sessionDispatcher, identity, TlsManualSocketDialer(keyManager))

    override suspend fun connect(
        address: String,
        port: Int,
    ): PairingConnection =
        openPairingConnection(keyManager, clock, ioDispatcher, sessionDispatcher, identity) {
            dialer.dial(address, port)
        }
}

/** Blocking, unpinned mTLS dial: the handshaked stream plus the peer leaf's SPKI DER. */
internal fun interface ManualSocketDialer {
    fun dial(
        address: String,
        port: Int,
    ): Pair<ByteStream, ByteArray>
}

internal class TlsManualSocketDialer(
    private val keyManager: X509KeyManager,
) : ManualSocketDialer {
    override fun dial(
        address: String,
        port: Int,
    ): Pair<ByteStream, ByteArray> {
        val factory = SslClientFactory(keyManager, UnpinnedPeerTrustManager())
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
