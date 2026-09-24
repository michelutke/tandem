package com.tandem.spike.e2ehandshake

import java.net.Socket
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.X509Certificate
import javax.net.ssl.SSLEngine
import javax.net.ssl.X509ExtendedKeyManager

/**
 * Presents a single AndroidKeyStore-backed identity (alias) as the client certificate for every
 * TLS handshake. This is the client-auth half of the E03-03 spike: SSLSocket asks this KeyManager
 * for an alias, then for the chain and PrivateKey handle for that alias; the PrivateKey handle is
 * an opaque AndroidKeyStore reference, never raw key material.
 */
class KeystoreKeyManager(private val alias: String) : X509ExtendedKeyManager() {

    override fun getClientAliases(keyType: String?, issuers: Array<Principal>?): Array<String> =
        arrayOf(alias)

    override fun chooseClientAlias(
        keyType: Array<out String>?,
        issuers: Array<out Principal>?,
        socket: Socket?,
    ): String = alias

    override fun chooseEngineClientAlias(
        keyType: Array<out String>?,
        issuers: Array<out Principal>?,
        engine: SSLEngine?,
    ): String = alias

    override fun getCertificateChain(alias: String?): Array<X509Certificate> {
        android.util.Log.i("E0304Spike", "getCertificateChain(alias=$alias)")
        val chain = KeystoreIdentity.certificateChain(this.alias)
        android.util.Log.i("E0304Spike", "getCertificateChain -> ${chain.size} certs, leaf sigAlg=${chain[0].sigAlgName}")
        return chain
    }

    override fun getPrivateKey(alias: String?): PrivateKey {
        android.util.Log.i("E0304Spike", "getPrivateKey(alias=$alias)")
        val key = KeystoreIdentity.privateKey(this.alias)
        android.util.Log.i("E0304Spike", "getPrivateKey -> algorithm=${key.algorithm} class=${key.javaClass.name}")
        return key
    }

    override fun getServerAliases(keyType: String?, issuers: Array<Principal>?): Array<String>? = null

    override fun chooseServerAlias(
        keyType: String?,
        issuers: Array<out Principal>?,
        socket: Socket?,
    ): String? = null
}
