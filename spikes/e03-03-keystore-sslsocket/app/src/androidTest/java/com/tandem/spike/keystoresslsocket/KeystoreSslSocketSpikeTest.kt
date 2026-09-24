package com.tandem.spike.keystoresslsocket

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import javax.net.ssl.SSLHandshakeException

private const val TAG = "E0303Spike"
private const val ALIAS = "e03-03-spike-identity"
private const val RUNS = 10

/**
 * E03-03 spike: SSLSocket (platform Conscrypt) client auth with an AndroidKeyStore P-256 key.
 * Every assertion here is one line of the go/no-go table in docs/spikes/android-sslsocket-keystore.md;
 * failures are recorded there, not hidden.
 *
 * Run against `openssl s_server` instances started by
 * spikes/e03-03-keystore-sslsocket/scripts/run-spike.sh, which passes ports/pin via
 * `-e host/mainPort/tls12Port/exporterPort/expectedPin`.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class KeystoreSslSocketSpikeTest {

    @Test
    fun test01_generateKey_reportsSecurityLevelAndNonExportable() {
        val generated = KeystoreIdentity.generateP256(ALIAS, preferStrongBox = true)
        val keyInfo = KeystoreIdentity.keyInfo(ALIAS)
        val privateKey = KeystoreIdentity.privateKey(ALIAS)

        Log.i(TAG, "securityLevel=${KeystoreIdentity.securityLevelName(keyInfo)} " +
            "requestedStrongBox=${generated.requestedStrongBox} strongBoxGranted=${generated.strongBoxGranted} " +
            "insideSecureHardware=${keyInfo.isInsideSecureHardware}")

        assertTrue("private key must not expose raw key material", privateKey.encoded == null)
        // Emulators back AndroidKeyStore with a software keymaster (no TEE/StrongBox), so
        // isInsideSecureHardware is expected to be false here; the go/no-go on secure-hardware
        // backing is a physical-device manual gate (see docs/spikes/android-sslsocket-keystore.md).
        if (!keyInfo.isInsideSecureHardware) {
            Log.w(TAG, "key is NOT inside secure hardware (expected on an emulator; manual gate on physical devices)")
        }
    }

    @Test
    fun test02_handshake_tls13ClientCert_10of10_alpnNegotiated() {
        val keyManager = KeystoreKeyManager(ALIAS)
        val trustManager = PinningTrustManager(SpikeArgs.expectedPinHex)
        val latencies = mutableListOf<Long>()

        repeat(RUNS) { i ->
            val context = TlsHandshakeClient.newContext(keyManager, trustManager, arrayOf("TLSv1.3"))
            val (socket, result) = TlsHandshakeClient.handshake(
                context = context,
                host = SpikeArgs.host,
                port = SpikeArgs.mainPort,
                protocols = arrayOf("TLSv1.3"),
            )
            socket.close()

            Log.i(TAG, "run=$i latencyMs=${result.latencyMs} protocol=${result.protocolVersion} " +
                "cipher=${result.cipherSuite} alpn=${result.negotiatedProtocol}")

            assertEquals("TLSv1.3", result.protocolVersion)
            assertEquals("tandem/1", result.negotiatedProtocol)
            latencies += result.latencyMs
        }

        val sorted = latencies.sorted()
        val p50 = sorted[RUNS / 2]
        val p95 = sorted[(RUNS * 95 / 100).coerceAtMost(RUNS - 1)]
        Log.i(TAG, "latency_p50Ms=$p50 latency_p95Ms=$p95 all=$sorted")
    }

    @Test
    fun test03_pinMismatch_rejected_10of10() {
        val keyManager = KeystoreKeyManager(ALIAS)
        val wrongPin = flipLastHexDigit(SpikeArgs.expectedPinHex)
        val trustManager = PinningTrustManager(wrongPin)

        repeat(RUNS) { i ->
            val context = TlsHandshakeClient.newContext(keyManager, trustManager, arrayOf("TLSv1.3"))
            try {
                val (socket, _) = TlsHandshakeClient.handshake(
                    context = context,
                    host = SpikeArgs.host,
                    port = SpikeArgs.mainPort,
                    protocols = arrayOf("TLSv1.3"),
                )
                socket.close()
                fail("run=$i: handshake succeeded despite SPKI pin mismatch")
            } catch (e: HandshakeFailed) {
                Log.i(TAG, "run=$i pin mismatch correctly rejected: ${e.cause?.message}")
            }
        }
    }

    @Test
    fun test04_clientRestrictedToTls13_rejectsTls12Server() {
        val keyManager = KeystoreKeyManager(ALIAS)
        val trustManager = PinningTrustManager(SpikeArgs.expectedPinHex)
        // A general "TLS" context (not the TLS1.3-only algorithm name) so the protocol restriction
        // below is doing the enforcement, matching how a real client would be configured.
        val context = javax.net.ssl.SSLContext.getInstance("TLS")
        context.init(arrayOf(keyManager), arrayOf(trustManager), null)

        try {
            val (socket, _) = TlsHandshakeClient.handshake(
                context = context,
                host = SpikeArgs.host,
                port = SpikeArgs.tls12Port,
                protocols = arrayOf("TLSv1.3"),
            )
            socket.close()
            fail("handshake succeeded against a TLS1.2-only server despite client restricted to TLSv1.3")
        } catch (e: HandshakeFailed) {
            Log.i(TAG, "TLS1.2 server correctly refused: ${e.cause?.message}")
            assertTrue(e.cause is SSLHandshakeException || e.cause != null)
        }
    }

    @Test
    fun test05_exporterKeyingMaterial_loggedFor10Runs() {
        val keyManager = KeystoreKeyManager(ALIAS)
        val trustManager = PinningTrustManager(SpikeArgs.expectedPinHex)

        repeat(RUNS) { i ->
            val context = TlsHandshakeClient.newContext(keyManager, trustManager, arrayOf("TLSv1.3"))
            val (socket, _) = TlsHandshakeClient.handshake(
                context = context,
                host = SpikeArgs.host,
                port = SpikeArgs.exporterPort,
                protocols = arrayOf("TLSv1.3"),
            )
            val exported = TlsHandshakeClient.exportKeyingMaterialOrNull(
                socket,
                "EXPORTER-Channel-Binding",
                ByteArray(0),
                32,
            )
            socket.close()

            if (exported == null) {
                Log.i(TAG, "run=$i exportKeyingMaterial unavailable (API < 31, SDK_INT=${android.os.Build.VERSION.SDK_INT})")
            } else {
                Log.i(TAG, "run=$i exporter=${exported.joinToString("") { "%02x".format(it) }}")
            }
        }
    }

    @Test
    fun test06_freshContextPerHandshake_setUseSessionTicketsDisabled_noCrash() {
        // Every handshake in this spike already uses a brand-new SSLContext (no session cache),
        // so there is nothing to resume; this test only confirms setUseSessionTickets(false) is
        // callable pre-handshake without side effects. Wire-level confirmation that the resulting
        // ClientHello carries no pre_shared_key extension is done via `openssl s_server -trace`
        // (see docs/spikes/android-sslsocket-keystore.md).
        val keyManager = KeystoreKeyManager(ALIAS)
        val trustManager = PinningTrustManager(SpikeArgs.expectedPinHex)
        val context = TlsHandshakeClient.newContext(keyManager, trustManager, arrayOf("TLSv1.3"))
        val (socket, result) = TlsHandshakeClient.handshake(
            context = context,
            host = SpikeArgs.host,
            port = SpikeArgs.mainPort,
            protocols = arrayOf("TLSv1.3"),
            disableSessionTickets = true,
        )
        socket.close()
        Log.i(TAG, "setUseSessionTickets(false) handshake ok: protocol=${result.protocolVersion}")
    }

    private fun flipLastHexDigit(hex: String): String {
        val last = hex.last()
        val flipped = if (last == '0') '1' else '0'
        return hex.dropLast(1) + flipped
    }
}
