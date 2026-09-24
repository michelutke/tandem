package com.tandem.spike.e2ehandshake

import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.X509TrustManager

/**
 * Trust is bound to the SPKI SHA-256 fingerprint of the leaf certificate only — never to a CA
 * chain, an IP address, or a device id. Any mismatch fails closed.
 */
class PinningTrustManager(private val expectedSpkiSha256Hex: String) : X509TrustManager {

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        throw CertificateException("client trust checking not used by this spike client")
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        val leaf = chain?.firstOrNull()
            ?: throw CertificateException("empty certificate chain")
        val actual = spkiSha256Hex(leaf)
        android.util.Log.i(
            "E0304Spike",
            "checkServerTrusted authType=$authType chainLen=${chain.size} expected=$expectedSpkiSha256Hex actual=$actual",
        )
        if (!constantTimeEquals(actual, expectedSpkiSha256Hex)) {
            throw CertificateException(
                "SPKI pin mismatch: expected=$expectedSpkiSha256Hex actual=$actual",
            )
        }
    }

    override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()

    companion object {
        fun spkiSha256Hex(cert: X509Certificate): String {
            val spki = cert.publicKey.encoded
            val digest = MessageDigest.getInstance("SHA-256").digest(spki)
            return digest.joinToString("") { "%02x".format(it) }
        }

        private fun constantTimeEquals(a: String, b: String): Boolean {
            if (a.length != b.length) return false
            var result = 0
            for (i in a.indices) {
                result = result or (a[i].code xor b[i].code)
            }
            return result == 0
        }
    }
}
