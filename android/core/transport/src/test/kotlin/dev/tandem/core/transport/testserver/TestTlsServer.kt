package dev.tandem.core.transport.testserver

import dev.tandem.core.transport.tls.TANDEM_ALPN_PROTOCOL
import org.conscrypt.Conscrypt
import java.io.Closeable
import java.net.InetAddress
import java.security.cert.X509Certificate
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509KeyManager
import javax.net.ssl.X509TrustManager

/** Per-connection knobs for [TestTlsServer] (E12-04 acceptance: TLS-1.2-only, ALPN mismatch, client-auth-required). */
data class TestTlsServerConfig(
    val enabledProtocols: Array<String> = arrayOf("TLSv1.3"),
    val alpnProtocols: Array<String> = arrayOf(TANDEM_ALPN_PROTOCOL),
    val requireClientAuth: Boolean = false,
)

/** What the server observed on the one connection it accepted. */
data class TestTlsConnectionResult(
    val handshakeError: Throwable?,
    val clientCertificate: X509Certificate?,
    val applicationBytesReceived: Int,
)

/**
 * A JVM-only Conscrypt `SSLServerSocket` on `127.0.0.1` (E12-04 test harness): the peer the
 * `integration:` tests dial to exercise a real TLS 1.3 handshake against `SslClientFactory`. Test
 * source set only — never a main source set (invariant 4: the Android app opens no listening
 * sockets; the no-listener lint, `NoListenerSockets.kt`, excludes test sources the same way).
 */
class TestTlsServer(
    keyManager: X509KeyManager,
    trustManager: X509TrustManager,
    private val config: TestTlsServerConfig = TestTlsServerConfig(),
) : Closeable {
    private val executor = Executors.newCachedThreadPool()
    private val serverSocket: SSLServerSocket

    init {
        val provider = Conscrypt.newProvider()
        val context = SSLContext.getInstance("TLS", provider)
        context.init(arrayOf(keyManager), arrayOf(trustManager), null)
        serverSocket =
            context.serverSocketFactory
                .createServerSocket(0, 50, InetAddress.getByName("127.0.0.1")) as SSLServerSocket
        serverSocket.enabledProtocols = config.enabledProtocols
        serverSocket.needClientAuth = config.requireClientAuth
    }

    val port: Int get() = serverSocket.localPort

    /** Accepts exactly one connection on a background thread and reports the outcome. */
    fun acceptOnce(): CompletableFuture<TestTlsConnectionResult> {
        val future = CompletableFuture<TestTlsConnectionResult>()
        executor.submit {
            try {
                future.complete(handleOneConnection())
            } catch (t: Throwable) {
                future.completeExceptionally(t)
            }
        }
        return future
    }

    private fun handleOneConnection(): TestTlsConnectionResult {
        val socket = serverSocket.accept() as SSLSocket
        val parameters = socket.sslParameters
        parameters.applicationProtocols = config.alpnProtocols
        socket.sslParameters = parameters

        var handshakeError: Throwable? = null
        var clientCertificate: X509Certificate? = null
        var applicationBytesReceived = 0
        try {
            socket.startHandshake()
            clientCertificate =
                runCatching { socket.session.peerCertificates.firstOrNull() as? X509Certificate }.getOrNull()
            val buffer = ByteArray(BUFFER_SIZE)
            val read = socket.inputStream.read(buffer)
            if (read > 0) applicationBytesReceived += read
        } catch (t: Throwable) {
            handshakeError = t
        } finally {
            runCatching { socket.close() }
        }
        return TestTlsConnectionResult(handshakeError, clientCertificate, applicationBytesReceived)
    }

    override fun close() {
        serverSocket.close()
        executor.shutdownNow()
    }

    private companion object {
        const val BUFFER_SIZE = 256
    }
}
