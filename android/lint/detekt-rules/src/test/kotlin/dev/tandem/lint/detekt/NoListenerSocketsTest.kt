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
