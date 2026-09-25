package dev.tandem.core.crypto

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.Signature

private const val ALIAS = "alias"

class IdentityKeyManagerTest {
    private val clock = TestClock(TestCoroutineScheduler())

    @Test
    fun keyManager_chooseClientAliasAnyKeyTypes_returnsFixedIdentityAlias() {
        val keyManager = IdentityKeyManager(SoftwareIdentityKeyStore(clock), ALIAS)

        assertEquals(ALIAS, keyManager.chooseClientAlias(null, null, null))
        assertEquals(ALIAS, keyManager.chooseClientAlias(arrayOf("RSA"), null, null))
        assertEquals(ALIAS, keyManager.chooseClientAlias(arrayOf("EC", "RSA"), arrayOf(), null))
        assertEquals(ALIAS, keyManager.chooseEngineClientAlias(arrayOf("EC"), null, null))
        assertArrayEquals(arrayOf(ALIAS), keyManager.getClientAliases("EC", null))
    }

    @Test
    fun keyManager_getCertificateChain_returnsSingleIdentityCert() {
        val store = SoftwareIdentityKeyStore(clock)
        val handle = store.getOrCreate(ALIAS, preferStrongBox = true)
        val keyManager = IdentityKeyManager(store, ALIAS)

        val chain = keyManager.getCertificateChain(ALIAS)

        assertEquals(1, chain.size)
        assertEquals(handle.certificate, chain[0])
    }

    @Test
    fun keyManager_privateKeySignature_verifiesWithChainPublicKey() {
        val store = SoftwareIdentityKeyStore(clock)
        store.getOrCreate(ALIAS, preferStrongBox = true)
        val keyManager = IdentityKeyManager(store, ALIAS)
        val data = "tandem".toByteArray()

        val signature =
            Signature.getInstance("SHA256withECDSA").run {
                initSign(keyManager.getPrivateKey(ALIAS))
                update(data)
                sign()
            }

        val publicKey = keyManager.getCertificateChain(ALIAS)[0].publicKey
        assertTrue(
            Signature.getInstance("SHA256withECDSA").run {
                initVerify(publicKey)
                update(data)
                verify(signature)
            },
        )
    }

    @Test
    fun keyManager_chooseServerAlias_returnsNull() {
        val keyManager = IdentityKeyManager(SoftwareIdentityKeyStore(clock), ALIAS)

        assertNull(keyManager.chooseServerAlias("EC", null, null))
        assertNull(keyManager.getServerAliases("EC", null))
    }
}
