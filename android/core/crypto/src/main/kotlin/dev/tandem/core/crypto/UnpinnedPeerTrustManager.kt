package dev.tandem.core.crypto

import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.X509ExtendedTrustManager

/**
 * The TLS trust decision for a manual-pairing candidate connection only (E73-03, ADR-008): the Mac
 * is not pinned yet, so there is nothing to compare against, and the only check is the leaf-key
 * precondition (a pinnable uncompressed P-256 SPKI, SPEC.md §1 step 2). The TLS stack still enforces
 * `CertificateVerify`, so the peer proves possession of the key whose SPKI the caller then reads.
 * This grants no trust: nothing is pinned here, the Mac is pinned only after the owner confirms the
 * SAS, and a connection made with this manager may carry pairing messages and nothing else. It must
 * never back any connection to a paired Mac; those use [PinningTrustManager].
 */
class UnpinnedPeerTrustManager : X509ExtendedTrustManager() {
    override fun checkServerTrusted(
        chain: Array<out X509Certificate>?,
        authType: String?,
    ) = requirePinnableLeaf(chain)

    override fun checkServerTrusted(
        chain: Array<out X509Certificate>?,
        authType: String?,
        socket: java.net.Socket?,
    ) = requirePinnableLeaf(chain)

    override fun checkServerTrusted(
        chain: Array<out X509Certificate>?,
        authType: String?,
        engine: javax.net.ssl.SSLEngine?,
    ) = requirePinnableLeaf(chain)

    override fun checkClientTrusted(
        chain: Array<out X509Certificate>?,
        authType: String?,
    ): Unit = neverTrustClient()

    override fun checkClientTrusted(
        chain: Array<out X509Certificate>?,
        authType: String?,
        socket: java.net.Socket?,
    ): Unit = neverTrustClient()

    override fun checkClientTrusted(
        chain: Array<out X509Certificate>?,
        authType: String?,
        engine: javax.net.ssl.SSLEngine?,
    ): Unit = neverTrustClient()

    override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()

    private fun requirePinnableLeaf(chain: Array<out X509Certificate>?) {
        if (chain.isNullOrEmpty()) throw CertificateException("peer presented no certificate")
        try {
            spkiFingerprint(chain[0].publicKey.encoded)
        } catch (cause: SpkiFingerprintException) {
            throw CertificateException("leaf key is not a pinnable SPKI", cause)
        }
    }

    private fun neverTrustClient(): Nothing =
        throw CertificateException("phone never validates a client certificate, it never listens (invariant 4)")
}
