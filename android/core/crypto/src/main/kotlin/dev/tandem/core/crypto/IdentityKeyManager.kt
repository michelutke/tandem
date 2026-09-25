package dev.tandem.core.crypto

import java.security.Principal
import java.security.PrivateKey
import java.security.cert.X509Certificate
import javax.net.ssl.SSLEngine
import javax.net.ssl.X509ExtendedKeyManager

/**
 * TLS client-certificate selector (E12-06) for the phone's single identity key (E10-01/E10-02).
 * Always presents [alias] regardless of the requested key types or issuers: Tandem's TLS 1.3
 * handshake pins SPKI fingerprints (invariant 3), not CA-issued chains, so there is nothing else
 * to choose between. `getServerAliases`/`chooseServerAlias` always return null: the Android app
 * never accepts inbound connections (invariant 4), so it is never asked to present a server
 * certificate.
 *
 * [getPrivateKey] returns [keyStore]'s `PrivateKey` handle unchanged; on the real
 * `AndroidKeyStoreIdentityKeyStore` that handle's `encoded` is null (E00-21) and JSSE signs
 * through it via the AndroidKeyStore provider, so key material never leaves Keystore.
 *
 * The `Socket`-typed parameters below belong to the `X509ExtendedKeyManager`/`X509KeyManager`
 * contract itself; this protocol's TLS 1.3 handshake is always driven through the `SSLEngine`
 * overloads, so they are always null and never read here. They are referenced by
 * fully-qualified name rather than imported, keeping raw-socket usage (`SocketOnlyInTransport`,
 * E00-14) confined to `core/transport`.
 */
class IdentityKeyManager(
    private val keyStore: IdentityKeyStore,
    private val alias: String = IDENTITY_KEY_ALIAS,
) : X509ExtendedKeyManager() {
    override fun getClientAliases(
        keyType: String?,
        issuers: Array<Principal>?,
    ): Array<String> = arrayOf(alias)

    override fun chooseClientAlias(
        keyType: Array<out String>?,
        issuers: Array<out Principal>?,
        socket: java.net.Socket?,
    ): String = alias

    override fun chooseEngineClientAlias(
        keyType: Array<out String>?,
        issuers: Array<out Principal>?,
        engine: SSLEngine?,
    ): String = alias

    override fun getCertificateChain(alias: String?): Array<X509Certificate> = arrayOf(handle().certificate)

    override fun getPrivateKey(alias: String?): PrivateKey = handle().privateKey

    override fun getServerAliases(
        keyType: String?,
        issuers: Array<Principal>?,
    ): Array<String>? = null

    override fun chooseServerAlias(
        keyType: String?,
        issuers: Array<out Principal>?,
        socket: java.net.Socket?,
    ): String? = null

    private fun handle(): KeyHandle = keyStore.get(alias) ?: error("Identity key \"$alias\" has not been generated yet")
}
