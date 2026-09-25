package dev.tandem.core.crypto

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import java.security.KeyStore
import java.time.Clock

/**
 * E10-01 instrumented tests: the emulator has no StrongBox, so requesting it always throws the
 * platform's `StrongBoxUnavailableException` and `IdentityKeyProvider`'s TEE fallback runs for
 * real (see E00-21 notes on `tandem.android.instrumented`). StrongBox-granted security level and
 * `KeyInfo.isInsideSecureHardware=true` are manual gates (E00-23) on physical hardware only.
 */
@RunWith(AndroidJUnit4::class)
class AndroidKeyStoreIdentityKeyStoreTest {
    private val clock = Clock.systemUTC()

    @After
    fun tearDown() {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(IDENTITY_KEY_ALIAS)
    }

    @Test
    fun androidKeyStoreIdentity_emulatorWithoutStrongBox_generatesViaTeeFallback() {
        val handle = IdentityKeyProvider(AndroidKeyStoreIdentityKeyStore(clock)).getOrCreateIdentityKey()

        assertNotNull(handle.publicKey)
        assertNotNull(AndroidKeyStoreIdentityKeyStore(clock).get(IDENTITY_KEY_ALIAS))
    }

    @Test
    fun androidKeyStoreIdentity_privateKey_encodedReturnsNull() {
        val handle = IdentityKeyProvider(AndroidKeyStoreIdentityKeyStore(clock)).getOrCreateIdentityKey()

        assertNull(handle.privateKey.encoded)
    }

    // E10-02: self-signed identity certificate over the Keystore key.
    @Test
    fun selfSignedCert_androidKeyStore_publicKeyEqualsKeystoreKey() {
        val handle = IdentityKeyProvider(AndroidKeyStoreIdentityKeyStore(clock)).getOrCreateIdentityKey()

        assertEquals(handle.publicKey, handle.certificate.publicKey)
    }

    @Test
    fun selfSignedCert_freshKeyStoreLoad_sameEncodedCertForAlias() {
        IdentityKeyProvider(AndroidKeyStoreIdentityKeyStore(clock)).getOrCreateIdentityKey()

        // Each new AndroidKeyStoreIdentityKeyStore() does its own fresh
        // KeyStore.getInstance("AndroidKeyStore").load(null), standing in for a process restart.
        val first = AndroidKeyStoreIdentityKeyStore(clock).get(IDENTITY_KEY_ALIAS)!!.certificate.encoded
        val second = AndroidKeyStoreIdentityKeyStore(clock).get(IDENTITY_KEY_ALIAS)!!.certificate.encoded

        assertArrayEquals(first, second)
    }
}
