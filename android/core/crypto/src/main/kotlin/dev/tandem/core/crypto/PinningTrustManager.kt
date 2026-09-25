package dev.tandem.core.crypto

import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.X509ExtendedTrustManager

/**
 * The entire TLS trust decision for the phone (SPEC.md §1, "Verify-callback algorithm"): the
 * phone is a TLS client only and never listens (invariant 4), so it never has the Mac's
 * pairing-window carve-out — the [pinSource] passed in always fully determines what is accepted.
 * There is no fallback to a system/default `TrustManagerFactory` or any CA-based trust path
 * anywhere in this class.
 *
 * `checkServerTrusted`'s three overloads all funnel through [verifyServer] and
 * [requirePinnableLeafFingerprint]: leaf-only — this implementation requires the peer send exactly
 * one certificate and rejects any chain with zero or more than one, rather than examining only
 * `chain[0]` and silently ignoring the rest (SPEC.md §1 "Certificate handling and the leaf-only
 * check" only mandates the latter; rejecting outright is a stricter, still-conforming choice for
 * this issue) — then the leaf-key-shape precondition
 * ([spkiFingerprint]'s own P-256/91-byte check, SPEC.md §1 step 2, which must fail before the pin
 * compare in step 3/4 ever runs), then a [constantTimeEquals] compare (invariant 6) against every
 * fingerprint [pinSource] currently returns. Certificate validity dates and every other X.509
 * field (subject, issuer, SAN, EKU, KU) are never inspected — trust is the SPKI pin alone, so an
 * expired-but-pinned certificate still passes here (`CertificateVerify` is still enforced by the
 * TLS stack independently of this callback, SPEC.md §1, E03-01/E03-03).
 *
 * `checkClientTrusted` always throws: the phone never validates a client certificate, since it
 * never accepts an inbound connection to have one on (invariant 4).
 *
 * The `Socket`/`SSLEngine` parameters below belong to the `X509ExtendedTrustManager` contract
 * itself; this pin check never needs a hostname or address (trust is bound to SPKI fingerprints
 * only, invariant 3), so they are never read here. They are referenced by fully-qualified name
 * rather than imported, matching `IdentityKeyManager.kt`'s existing socket-avoidance convention.
 */
class PinningTrustManager(
    private val pinSource: PinSource,
) : X509ExtendedTrustManager() {
    override fun checkServerTrusted(
        chain: Array<out X509Certificate>?,
        authType: String?,
    ) = verifyServer(chain)

    override fun checkServerTrusted(
        chain: Array<out X509Certificate>?,
        authType: String?,
        socket: java.net.Socket?,
    ) = verifyServer(chain)

    override fun checkServerTrusted(
        chain: Array<out X509Certificate>?,
        authType: String?,
        engine: javax.net.ssl.SSLEngine?,
    ) = verifyServer(chain)

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

    private fun verifyServer(chain: Array<out X509Certificate>?) {
        val candidate = requirePinnableLeafFingerprint(chain)
        val pinned = pinSource.expectedFingerprints().any { constantTimeEquals(candidate.bytes, it.bytes) }
        if (!pinned) {
            throw CertificateException("presented SPKI fingerprint does not match any pinned fingerprint")
        }
    }

    private fun requirePinnableLeafFingerprint(chain: Array<out X509Certificate>?): SpkiFingerprint {
        if (chain == null || chain.size != 1) {
            throw CertificateException("expected exactly one leaf certificate, got ${chain?.size ?: 0}")
        }
        return try {
            spkiFingerprint(chain[0].publicKey.encoded)
        } catch (cause: SpkiFingerprintException) {
            throw CertificateException("leaf key is not a pinnable SPKI", cause)
        }
    }

    private fun neverTrustClient(): Nothing =
        throw CertificateException("phone never validates a client certificate, it never listens (invariant 4)")
}
