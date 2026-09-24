package dev.tandem.core.crypto

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.security.KeyPairGenerator
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec

@RunWith(AndroidJUnit4::class)
class SampleKeystoreTest {
    @Test
    fun sampleKeystoreTest_androidKeyStoreProvider_generatesP256Key() {
        val keyPairGenerator =
            KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                "AndroidKeyStore",
            )
        keyPairGenerator.initialize(
            KeyGenParameterSpec
                .Builder(
                    "tandem.e00-21.sample-key",
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                ).setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .build(),
        )

        val keyPair = keyPairGenerator.generateKeyPair()

        val publicKey = keyPair.public as ECPublicKey
        assertEquals("EC", publicKey.algorithm)
        assertEquals(256, publicKey.params.curve.field.fieldSize)
    }
}
