package com.tandem.spike.e2ehandshake

import android.os.Build
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.security.MessageDigest

private const val TAG = "E0304Spike"

/**
 * E03-04 experiment 1: 10 real mTLS 1.3 handshakes against the macOS `e2e-mac` listener
 * (spikes/e03-04-e2e/mac, wiring together E03-01's server and E03-03's Android client), asserting
 * TLS 1.3 + ALPN `tandem/1` every time and recording the RFC 9266 exporter (API 31+ only -- see
 * ChallengeHandshakeTest for the API 29/30 fallback path). Only the SHA-256 of the exporter is
 * logged, never the raw secret (matches the convention already established in E03-01/E03-03), so
 * `scripts/run-e2e.sh` compares this side's logcat against the Mac listener's own
 * `exporter_sha256` log line for the same run index.
 */
@RunWith(AndroidJUnit4::class)
class ExporterHandshakeTest {

    @Test
    fun handshake10x_tls13_alpnTandem1_exporterRecorded() {
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

            assertEquals("TLSv1.3", result.protocolVersion)
            assertEquals("tandem/1", result.negotiatedProtocol)

            // The Mac listener (spikes/e03-04-e2e/mac) only transitions Network.framework's
            // connection state to `.ready` -- which is what makes it log `exporter_sha256` -- once
            // it has actually processed the client's Finished message and is servicing the
            // connection. Closing the socket the instant `startHandshake()` returns, with zero
            // bytes of application data ever sent, races that transition: Network.framework can
            // observe the TCP FIN before its own handshake bookkeeping completes and report
            // `.failed(-9816 "closed session with no notification")` instead of `.ready`. A real
            // hello/ack round trip (matched by the Mac's default, non-challenge listener mode)
            // avoids the race and is what every other spike here already does.
            val output = socket.outputStream
            val input = socket.inputStream
            output.write("hello\n".toByteArray())
            output.flush()
            val ackByte = input.read()
            check(ackByte >= 0) { "run=$i: server closed before sending ack" }

            val exported = TlsHandshakeClient.exportKeyingMaterialOrNull(
                socket,
                "EXPORTER-Channel-Binding",
                ByteArray(0),
                32,
            )
            socket.close()

            if (exported == null) {
                Log.i(TAG, "run=$i sdkInt=${Build.VERSION.SDK_INT} exporter unavailable")
            } else {
                val sha = MessageDigest.getInstance("SHA-256").digest(exported)
                    .joinToString("") { "%02x".format(it) }
                Log.i(TAG, "run=$i latencyMs=${result.latencyMs} exporter_sha256=$sha")
            }

            if (Build.VERSION.SDK_INT >= 31) {
                assertNotNull("exporter must be available on API 31+", exported)
            }
        }
    }
}
