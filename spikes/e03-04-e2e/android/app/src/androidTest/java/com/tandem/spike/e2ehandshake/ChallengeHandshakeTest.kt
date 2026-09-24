package com.tandem.spike.e2ehandshake

import android.os.Build
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

private const val TAG = "E0304Spike"

/**
 * E03-04 experiment 2: the API 29/30 fallback for channel binding. First confirms
 * `exportKeyingMaterial` really is unavailable on this device (D-15's premise for needing a
 * fallback at all), then runs the in-band challenge exchange (see `ChallengeClient`) against the
 * macOS listener started with `--challenge`. The Mac side verifies the signature and logs
 * `EVENT type=challenge-verified ... match=true`; this test additionally asserts the ack byte the
 * listener sends back so a single instrumentation run gives a pass/fail without needing to scrape
 * the Mac log (the Mac log is still captured for the findings doc's evidence section).
 */
@RunWith(AndroidJUnit4::class)
class ChallengeHandshakeTest {

    @Test
    fun exporterUnavailable_inBandChallengeSucceeds10x() {
        val keyManager = KeystoreKeyManager(SpikeConstants.ALIAS)
        val trustManager = PinningTrustManager(SpikeArgs.expectedServerPinHex)

        repeat(SpikeConstants.RUNS) { i ->
            val context = TlsHandshakeClient.newContext(keyManager, trustManager, arrayOf("TLSv1.3"))
            val (socket, result) = TlsHandshakeClient.handshake(
                context = context,
                host = SpikeArgs.host,
                port = SpikeArgs.port,
                protocols = arrayOf("TLSv1.3"),
            )
            Log.i(TAG, "run=$i handshake ok sdkInt=${Build.VERSION.SDK_INT} protocol=${result.protocolVersion} alpn=${result.negotiatedProtocol}")

            val exported = TlsHandshakeClient.exportKeyingMaterialOrNull(socket, "EXPORTER-Channel-Binding", ByteArray(0), 32)
            assertNull("run=$i: exportKeyingMaterial must be unavailable below API 31 (this test targets that gap)", exported)

            val challengeResult = ChallengeClient.respond(socket, SpikeConstants.ALIAS)
            socket.close()

            Log.i(
                TAG,
                "run=$i challenge_sha256=${challengeResult.challengeSha256Hex} ackOk=${challengeResult.ackOk} " +
                    "latencyMs=${challengeResult.latencyMs}",
            )
            assertTrue("run=$i: Mac listener must ack a valid signature over the challenge", challengeResult.ackOk)
        }
    }
}
