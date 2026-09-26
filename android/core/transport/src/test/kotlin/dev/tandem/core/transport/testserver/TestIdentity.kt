package dev.tandem.core.transport.testserver

import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.SoftwareIdentityKeyStore
import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.test.TestCoroutineScheduler
import java.security.PrivateKey
import java.security.cert.X509Certificate

/** A generated P-256 identity (E10-15, JVM fake) plus the [IdentityKeyManager] that presents it. */
class TestIdentity(
    val alias: String,
) {
    private val store = SoftwareIdentityKeyStore(TestClock(TestCoroutineScheduler()))
    val keyManager: IdentityKeyManager

    init {
        ConscryptProviderInstaller.ensureInstalled()
        store.getOrCreate(alias, preferStrongBox = false)
        keyManager = IdentityKeyManager(store, alias)
    }

    val certificate: X509Certificate
        get() = keyManager.getCertificateChain(alias = null).single()

    val privateKey: PrivateKey
        get() = keyManager.getPrivateKey(alias = null)
}
