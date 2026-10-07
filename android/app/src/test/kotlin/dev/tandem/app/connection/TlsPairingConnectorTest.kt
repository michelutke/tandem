package dev.tandem.app.connection

import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.ByteStream
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.PrivateKey
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.X509KeyManager

class TlsPairingConnectorTest {
    @Test
    fun connect_socketOpensAfterCancellation_streamClosed() =
        runTest {
            val stream = RecordingByteStream()
            var callerJob: Job? = null
            val dispatcher = StandardTestDispatcher(testScheduler)
            val connector =
                connector(dispatcher) { _, _, _ ->
                    callerJob?.cancel()
                    stream to ByteArray(0)
                }

            val job = backgroundScope.launch(dispatcher) { connector.connect("10.0.0.2", 8443) { emptyList() } }
            callerJob = job
            job.join()

            assertTrue(job.isCancelled)
            assertTrue(stream.closed)
        }

    @Test
    fun connect_pinningRejectsPeer_throwsCertificateException() =
        runTest {
            val connector =
                connector(StandardTestDispatcher(testScheduler)) { _, _, _ ->
                    throw SSLHandshakeException("handshake failed").apply {
                        initCause(CertificateException("no pin matches"))
                    }
                }

            val thrown = runCatching { connector.connect("10.0.0.2", 8443) { emptyList() } }.exceptionOrNull()

            assertTrue(thrown is CertificateException)
        }

    @Test
    fun connect_plainIoFailure_propagatesAsIoException() =
        runTest {
            val connector =
                connector(StandardTestDispatcher(testScheduler)) { _, _, _ -> throw IOException("refused") }

            val thrown = runCatching { connector.connect("10.0.0.2", 8443) { emptyList() } }.exceptionOrNull()

            assertTrue(thrown is IOException)
        }

    @Test
    fun connect_identityBootstrapFails_throwsIdentityUnavailableWithoutDialing() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            var dialed = false
            val connector =
                connector(dispatcher, IdentityBootstrap({ error("keystore") }, dispatcher)) { _, _, _ ->
                    dialed = true
                    throw IOException("unreachable")
                }

            val thrown = runCatching { connector.connect("10.0.0.2", 8443) { emptyList() } }.exceptionOrNull()

            assertTrue(thrown is dev.tandem.core.pairing.IdentityUnavailableException)
            assertFalse(dialed)
        }

    @Test
    fun connect_awaitsIdentityBootstrapBeforeDialing() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            val events = mutableListOf<String>()
            val connector =
                connector(dispatcher, IdentityBootstrap({ events += "bootstrap" }, dispatcher)) { _, _, _ ->
                    events += "dial"
                    throw IOException("refused")
                }

            runCatching { connector.connect("10.0.0.2", 8443) { emptyList() } }

            assertEquals(listOf("bootstrap", "dial"), events)
        }

    private fun TestScope.connector(
        dispatcher: CoroutineDispatcher,
        identity: IdentityBootstrap = IdentityBootstrap({}, dispatcher),
        dialer: PairingSocketDialer,
    ) = TlsPairingConnector(UnusedKeyManager, TestClock(testScheduler), dispatcher, dispatcher, identity, dialer)

    private class RecordingByteStream : ByteStream {
        var closed = false
        override val input: InputStream = ByteArrayInputStream(ByteArray(0))
        override val output: OutputStream = ByteArrayOutputStream()

        override fun closeGracefully() {
            closed = true
        }

        override fun closeAbruptly() {
            closed = true
        }
    }

    private object UnusedKeyManager : X509KeyManager {
        override fun getClientAliases(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
        ): Array<String>? = null

        override fun chooseClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out java.security.Principal>?,
            socket: java.net.Socket?,
        ): String? = null

        override fun getServerAliases(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
        ): Array<String>? = null

        override fun chooseServerAlias(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
            socket: java.net.Socket?,
        ): String? = null

        override fun getCertificateChain(alias: String?): Array<X509Certificate>? = null

        override fun getPrivateKey(alias: String?): PrivateKey? = null
    }
}
