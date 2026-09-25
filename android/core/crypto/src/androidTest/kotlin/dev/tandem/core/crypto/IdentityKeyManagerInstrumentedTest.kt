package dev.tandem.core.crypto

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import java.security.KeyStore
import java.time.Clock

/**
 * E12-06 instrumented: on the emulator's real AndroidKeyStore, the `PrivateKey` handle
 * `IdentityKeyManager.getPrivateKey` returns is a Keystore reference whose `encoded` is null — the
 * key material itself never leaves Keystore (E00-21).
 */
@RunWith(AndroidJUnit4::class)
class IdentityKeyManagerInstrumentedTest {
    private val clock = Clock.systemUTC()

    @After
    fun tearDown() {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(IDENTITY_KEY_ALIAS)
    }

    @Test
    fun keyManager_androidKeyStorePrivateKey_encodedReturnsNull() {
        val keyStore = AndroidKeyStoreIdentityKeyStore(clock)
        IdentityKeyProvider(keyStore).getOrCreateIdentityKey()
        val keyManager = IdentityKeyManager(keyStore)

        val privateKey = keyManager.getPrivateKey(IDENTITY_KEY_ALIAS)

        assertNull(privateKey.encoded)
    }
}
