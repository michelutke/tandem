package dev.tandem.harness.jvmclient.testserver

import java.security.cert.X509Certificate
import javax.net.ssl.X509TrustManager

/**
 * Test-only [X509TrustManager] that accepts any peer certificate (mirrors `core/transport`'s own
 * `AcceptAnyTrustManager`, E12-04): the harness's self-test only needs the handshake to complete
 * on the server side, so the fake server uses this instead of any real trust decision.
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
