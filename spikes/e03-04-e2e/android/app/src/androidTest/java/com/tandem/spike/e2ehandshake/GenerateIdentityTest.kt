package com.tandem.spike.e2ehandshake

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith

private const val TAG = "E0304Spike"

/**
 * Phase 1 of the E03-04 harness (`scripts/run-e2e.sh`): generate (or regenerate) the
 * AndroidKeyStore identity this run will use as its TLS client certificate, and print its SPKI
 * SHA-256 pin so the driving script can write it into the macOS listener's expected-client-pin
 * file *before* starting the listener. Run in isolation via:
 *   adb shell am instrument -w -e class com.tandem.spike.e2ehandshake.GenerateIdentityTest ...
 */
@RunWith(AndroidJUnit4::class)
class GenerateIdentityTest {

    @Test
    fun generateKeyAndPrintPin() {
        KeystoreIdentity.generateP256(SpikeConstants.ALIAS, preferStrongBox = true)
        val chain = KeystoreIdentity.certificateChain(SpikeConstants.ALIAS)
        val pinHex = PinningTrustManager.spkiSha256Hex(chain[0])
        Log.i(TAG, "CLIENT_PIN=$pinHex")
    }
}
