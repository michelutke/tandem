package dev.tandem.core.transport.testserver

import java.security.cert.X509Certificate
import javax.net.ssl.X509TrustManager

/**
 * Test-only [X509TrustManager] that accepts any peer certificate. Pin checking is E12-05's job
 * (not yet implemented); this issue's tests only need the handshake to complete, so both the test
 * client and the test server use this instead of any real trust decision.
 */
class AcceptAnyTrustManager : X509TrustManager {
    override fun checkClientTrusted(
        chain: Array<out X509Certificate>,
        authType: String,
    ) = Unit

    override fun checkServerTrusted(
        chain: Array<out X509Certificate>,
        authType: String,
    ) = Unit

    override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
}
