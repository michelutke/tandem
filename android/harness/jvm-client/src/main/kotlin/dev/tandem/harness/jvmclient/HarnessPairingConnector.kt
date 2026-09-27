package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.pairing.PairingConnection
import dev.tandem.core.pairing.PairingConnector
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.tls.SslClientFactory
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.InetAddress
import java.security.cert.X509Certificate
import java.time.Clock

/**
 * [PairingConnector] for the JVM harness (E15-21): dials [address]:[port] with [identityKeyManager]
 * as the client certificate and a fresh [PinningTrustManager] pinned to [pinSource], the same way
 * the real (not yet written) Android production connector will. Harness-only: production
 * `core/pairing` never opens a socket itself (`PairingConnector` stays a seam — see its own kdoc);
 * this class is this module's, not `core/pairing`'s, first real implementation of it.
 */
class HarnessPairingConnector(
    private val identityKeyManager: IdentityKeyManager,
    private val dispatcher: CoroutineDispatcher,
) : PairingConnector {
    override suspend fun connect(
        address: String,
        port: Int,
        pinSource: PinSource,
    ): PairingConnection {
        HarnessConscryptProvider.ensureInstalled()
        val factory =
            SslClientFactory(identityKeyManager, PinningTrustManager(pinSource), JvmConscryptSessionTicketDisabler())
        val socket = factory.createSocket()
        val stream =
            withContext(dispatcher) {
                factory.connect(socket, InetAddress.getByName(address), port)
            }

        val session = ByteStreamSession(stream, Clock.systemUTC(), dispatcher)
        val outcome = session.state.first { it is ConnectionState.Ready || it is ConnectionState.Failed }
        if (outcome is ConnectionState.Failed) {
            session.close()
            throw IOException("harness pairing connect failed: ${outcome.reason}")
        }

        val macCertificate = socket.session.peerCertificates.first() as X509Certificate
        val phoneCertificate = identityKeyManager.getCertificateChain(alias = null).single()
        return PairingConnection(
            session = session,
            macSpkiDer = macCertificate.publicKey.encoded,
            phoneSpkiDer = phoneCertificate.publicKey.encoded,
        )
    }
}
