package dev.tandem.harness.jvmclient.testserver

import java.net.Socket
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.X509Certificate
import javax.net.ssl.SSLEngine
import javax.net.ssl.X509ExtendedKeyManager

/**
 * Test-only server-side key manager wrapping a [TestIdentity] (mirrors `core/transport`'s own
 * `TestServerKeyManager`, E12-04): the production `IdentityKeyManager` is client-only by design
 * (invariant 4, the phone never accepts inbound connections), so [TestTlsServer], which does need
 * to select a server alias, uses this instead.
 */
class TestServerKeyManager(
    private val identity: TestIdentity,
) : X509ExtendedKeyManager() {
    override fun getClientAliases(
        keyType: String?,
        issuers: Array<Principal>?,
    ): Array<String>? = null

    override fun chooseClientAlias(
        keyType: Array<out String>?,
        issuers: Array<out Principal>?,
        socket: Socket?,
    ): String? = null

    override fun chooseEngineClientAlias(
        keyType: Array<out String>?,
        issuers: Array<out Principal>?,
        engine: SSLEngine?,
    ): String? = null

    override fun getServerAliases(
        keyType: String?,
        issuers: Array<Principal>?,
    ): Array<String> = arrayOf(identity.alias)

    override fun chooseServerAlias(
        keyType: String?,
        issuers: Array<out Principal>?,
        socket: Socket?,
    ): String = identity.alias

    override fun chooseEngineServerAlias(
        keyType: String?,
        issuers: Array<out Principal>?,
        engine: SSLEngine?,
    ): String = identity.alias

    override fun getCertificateChain(alias: String?): Array<X509Certificate> = arrayOf(identity.certificate)

    override fun getPrivateKey(alias: String?): PrivateKey = identity.privateKey
}
