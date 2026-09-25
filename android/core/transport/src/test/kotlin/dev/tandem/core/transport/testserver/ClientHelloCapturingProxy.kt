package dev.tandem.core.transport.testserver

import java.io.Closeable
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * A transparent TCP relay between a test client and [targetPort] on `127.0.0.1` that records the
 * first TLS record the client sends (the plaintext `ClientHello`) before forwarding it unchanged,
 * so `integration:` tests can inspect the wire bytes of a real handshake
 * (`sslClient_serverIssuesTickets_secondClientHelloHasNoPsk`). Everything after that first record
 * is relayed byte-for-byte in both directions. Test-only: raw `ServerSocket`/`Socket` usage here
 * is exempt from the no-listener lint (test source sets only, invariant 4 applies to main sources).
 */
class ClientHelloCapturingProxy(
    private val targetPort: Int,
) : Closeable {
    private val listener = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
    private val executor = Executors.newCachedThreadPool()
    private val relayFinished = CountDownLatch(1)

    val port: Int get() = listener.localPort

    @Volatile
    var capturedClientHelloRecord: ByteArray? = null
        private set

    fun start() {
        executor.submit {
            val client =
                try {
                    listener.accept()
                } catch (_: IOException) {
                    relayFinished.countDown()
                    return@submit
                }
            relay(client)
        }
    }

    /** Blocks until the one relayed connection this proxy handles has fully closed. */
    fun awaitRelayFinished(timeoutSeconds: Long) {
        relayFinished.await(timeoutSeconds, TimeUnit.SECONDS)
    }

    private fun relay(client: Socket) {
        val upstream = Socket(InetAddress.getByName("127.0.0.1"), targetPort)

        val clientToUpstream =
            executor.submit {
                try {
                    val input = client.getInputStream()
                    val output = upstream.getOutputStream()
                    val header = input.readNBytes(5)
                    if (header.size == 5) {
                        val recordLength = ((header[3].toInt() and 0xFF) shl 8) or (header[4].toInt() and 0xFF)
                        val body = input.readNBytes(recordLength)
                        capturedClientHelloRecord = header + body
                        output.write(header)
                        output.write(body)
                        output.flush()
                    }
                    input.copyTo(output)
                } catch (_: IOException) {
                    // Peer closed; nothing more to relay in this direction.
                } finally {
                    runCatching { upstream.shutdownOutput() }
                }
            }

        val upstreamToClient =
            executor.submit {
                try {
                    upstream.getInputStream().copyTo(client.getOutputStream())
                } catch (_: IOException) {
                    // Peer closed; nothing more to relay in this direction.
                } finally {
                    runCatching { client.shutdownOutput() }
                }
            }

        clientToUpstream.get()
        upstreamToClient.get()
        runCatching { client.close() }
        runCatching { upstream.close() }
        relayFinished.countDown()
    }

    override fun close() {
        listener.close()
        executor.shutdownNow()
    }
}
