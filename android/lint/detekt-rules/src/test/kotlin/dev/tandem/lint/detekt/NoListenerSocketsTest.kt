package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.test.compileAndLint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * E12-04 tdd:
 *   ci: noListenerLint_serverSocketInMainSourceFixture_fails
 *   ci: noListenerLint_currentTree_passes
 *
 * The second tdd id is expressed here as zero findings on a fixture pasted from this issue's own
 * new main-source class (`SslClientFactory`'s socket-creation shape) plus the real `./gradlew
 * detekt` run (part of the verify command) actually passing on the whole tree, which is the
 * practical version of "current tree passes" for a rule with no module exclusion.
 */
class NoListenerSocketsTest {
    @Test
    fun noListenerLint_serverSocketInMainSourceFixture_fails() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import java.net.ServerSocket

                fun listen(): ServerSocket = ServerSocket(0)
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("NoListenerSockets", findings.single().id)
    }

    @Test
    fun noListenerLint_sslServerSocketImportInMainSourceFixture_fails() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import javax.net.ssl.SSLServerSocket

                fun describe(socket: SSLServerSocket): String = socket.toString()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("NoListenerSockets", findings.single().id)
    }

    @Test
    fun noListenerLint_serverSocketFactoryInferredTypeFixture_fails() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import javax.net.ssl.SSLContext

                fun listen() = SSLContext.getInstance("TLS").serverSocketFactory.createServerSocket(0).accept()
                """.trimIndent(),
            )

        assertTrue(findings.isNotEmpty())
        assertTrue(findings.all { it.id == "NoListenerSockets" })
    }

    @Test
    fun noListenerLint_asynchronousServerSocketChannelImportFixture_fails() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import java.nio.channels.AsynchronousServerSocketChannel

                fun listen(): AsynchronousServerSocketChannel = AsynchronousServerSocketChannel.open()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("NoListenerSockets", findings.single().id)
    }

    @Test
    fun noListenerLint_selectorProviderOpenServerSocketChannelFixture_fails() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import java.nio.channels.spi.SelectorProvider

                fun listen() = SelectorProvider.provider().openServerSocketChannel()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("NoListenerSockets", findings.single().id)
    }

    @Test
    fun noListenerLint_localServerSocketImportFixture_fails() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import android.net.LocalServerSocket

                fun listen(name: String): LocalServerSocket = LocalServerSocket(name)
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("NoListenerSockets", findings.single().id)
    }

    @Test
    fun noListenerLint_datagramSocketImportFixture_fails() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import java.net.DatagramSocket

                fun listen(port: Int): DatagramSocket = DatagramSocket(port)
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("NoListenerSockets", findings.single().id)
    }

    @Test
    fun noListenerLint_datagramChannelImportFixture_fails() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import java.nio.channels.DatagramChannel

                fun listen(): DatagramChannel = DatagramChannel.open()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("NoListenerSockets", findings.single().id)
    }

    @Test
    fun noListenerLint_nsdManagerRegisterServiceFixture_fails() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import android.net.nsd.NsdManager
                import android.net.nsd.NsdServiceInfo
                import android.net.nsd.NsdManager.RegistrationListener

                fun advertise(manager: NsdManager, info: NsdServiceInfo, listener: RegistrationListener) {
                    manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
                }
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("NoListenerSockets", findings.single().id)
    }

    @Test
    fun noListenerLint_currentTree_passes() {
        val findings =
            NoListenerSockets().compileAndLint(
                """
                import java.net.InetAddress
                import java.net.InetSocketAddress
                import javax.net.ssl.SSLContext
                import javax.net.ssl.SSLSocket
                import javax.net.ssl.X509KeyManager
                import javax.net.ssl.X509TrustManager

                class SslClientFactory(
                    private val keyManager: X509KeyManager,
                    private val trustManager: X509TrustManager,
                ) {
                    fun createSocket(): SSLSocket {
                        val context = SSLContext.getInstance("TLSv1.3")
                        context.init(arrayOf(keyManager), arrayOf(trustManager), null)
                        val socket = context.socketFactory.createSocket() as SSLSocket
                        socket.enabledProtocols = arrayOf("TLSv1.3")
                        return socket
                    }

                    fun connect(
                        socket: SSLSocket,
                        address: InetAddress,
                        port: Int,
                    ) {
                        socket.connect(InetSocketAddress(address, port))
                        socket.startHandshake()
                    }
                }
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }
}
