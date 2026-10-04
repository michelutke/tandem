package dev.tandem.core.transport.media

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.tls.AndroidSessionTicketDisabler
import dev.tandem.core.transport.tls.SessionTicketDisabler
import dev.tandem.core.transport.tls.SslClientFactory
import java.net.InetAddress
import javax.net.ssl.X509KeyManager

/**
 * Opens the media connection's [ByteStream] (E60-02, SPEC.md #media-ticket). CRITICAL (invariants 1,
 * 3, 5): an implementation MUST complete the full mTLS handshake with the peer authenticated against
 * [pinSource] before returning, and MUST throw (never return) when the peer fails that check, so no
 * application byte can reach an unpinned peer.
 */
fun interface MediaStreamFactory {
    fun open(
        address: CandidateAddress,
        pinSource: PinSource,
    ): ByteStream
}

/**
 * Production [MediaStreamFactory]: the same [SslClientFactory] TLS profile and [PinningTrustManager]
 * pin check the control connection uses, never a separate or relaxed trust path (SPEC.md #media-ticket).
 */
class PinnedTlsMediaStreamFactory(
    private val keyManager: X509KeyManager,
    private val sessionTicketDisabler: SessionTicketDisabler = AndroidSessionTicketDisabler(),
) : MediaStreamFactory {
    override fun open(
        address: CandidateAddress,
        pinSource: PinSource,
    ): ByteStream {
        val factory = SslClientFactory(keyManager, PinningTrustManager(pinSource), sessionTicketDisabler)
        return factory.connect(factory.createSocket(), InetAddress.getByName(address.host), address.port)
    }
}
