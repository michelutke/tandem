package dev.tandem.harness.jvmclient.testserver

import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.SoftwareIdentityKeyStore
import dev.tandem.core.testing.TestClock
import dev.tandem.harness.jvmclient.HarnessConscryptProvider
import kotlinx.coroutines.test.TestCoroutineScheduler
import java.security.PrivateKey
import java.security.cert.X509Certificate

/**
 * A generated P-256 identity (E10-15, JVM fake) plus the [IdentityKeyManager] that presents it
 * (mirrors `core/transport`'s own `TestIdentity`, E12-04): the fake in-process TLS server this
 * harness's self-test dials against uses this for its own server certificate.
 */
class TestIdentity(
    val alias: String,
) {
    private val store = SoftwareIdentityKeyStore(TestClock(TestCoroutineScheduler()))
    val keyManager: IdentityKeyManager

    init {
        HarnessConscryptProvider.ensureInstalled()
        store.getOrCreate(alias, preferStrongBox = false)
        keyManager = IdentityKeyManager(store, alias)
    }

    val certificate: X509Certificate
        get() = keyManager.getCertificateChain(alias = null).single()

    val privateKey: PrivateKey
        get() = keyManager.getPrivateKey(alias = null)
}
