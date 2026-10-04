package dev.tandem.app.connection

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.pairing.PairingConnection
import dev.tandem.core.pairing.PairingConnector
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.tls.SslClientFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.InetAddress
import java.security.cert.X509Certificate
import java.time.Clock
import javax.net.ssl.X509KeyManager

/**
 * Production [PairingConnector] (E20-26, invariants 1, 3, 5): dials the invite's Mac over mTLS with
 * a [PinningTrustManager] pinned to [PinSource] (the QR fingerprint, never the trust store), so no
 * [ByteStreamSession] -- and no application byte -- exists for a peer that fails the pin check. A
 * session that does not reach Ready (version mismatch, hello failure) is closed and fails closed.
 * Never listens (invariant 4).
 */
class TlsPairingConnector(
    private val keyManager: X509KeyManager,
    private val clock: Clock,
    private val ioDispatcher: CoroutineDispatcher,
    private val sessionDispatcher: CoroutineDispatcher,
) : PairingConnector {
    override suspend fun connect(
        address: String,
        port: Int,
        pinSource: PinSource,
    ): PairingConnection {
        val factory = SslClientFactory(keyManager, PinningTrustManager(pinSource))
        val (stream, macSpkiDer) =
            withContext(ioDispatcher) {
                val socket = factory.createSocket()
                val stream = factory.connect(socket, InetAddress.getByName(address), port)
                stream to
                    socket.session.peerCertificates
                        .first()
                        .publicKey.encoded
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
