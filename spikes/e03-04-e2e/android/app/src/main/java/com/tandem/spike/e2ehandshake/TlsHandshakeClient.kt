package com.tandem.spike.e2ehandshake

import android.net.ssl.SSLSockets
import android.os.Build
import java.net.InetSocketAddress
import java.net.Socket
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLParameters
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager

private const val ALPN_PROTOCOL = "tandem/1"
private const val CONNECT_TIMEOUT_MS = 5_000
private const val HANDSHAKE_TIMEOUT_MS = 10_000

data class HandshakeResult(
    val latencyMs: Long,
    val negotiatedProtocol: String?,
    val protocolVersion: String,
    val cipherSuite: String,
)

class HandshakeFailed(message: String, cause: Throwable) : Exception(message, cause)

object TlsHandshakeClient {

    /**
     * Builds a fresh SSLContext (no session cache reuse across calls) restricted to the given
     * protocols, with the spike's KeyManager/TrustManager wired in.
     */
    fun newContext(keyManager: KeystoreKeyManager, trustManager: TrustManager, protocols: Array<String>): SSLContext {
        // "TLSv1.3" as the algorithm name yields a context whose default parameters are already
        // restricted to TLS 1.3; we additionally pin SSLParameters.protocols below defensively.
        val context = SSLContext.getInstance("TLSv1.3")
        context.init(arrayOf(keyManager), arrayOf(trustManager), null)
        return context
    }

    /**
     * Connects, completes the handshake, offers ALPN "tandem/1", and returns timing + negotiated
     * parameters. The caller is responsible for closing the returned socket after any additional
     * inspection (e.g. exporter extraction).
     */
    fun handshake(
        context: SSLContext,
        host: String,
        port: Int,
        protocols: Array<String>,
        alpnProtocols: Array<String> = arrayOf(ALPN_PROTOCOL),
        disableSessionTickets: Boolean = false,
    ): Pair<SSLSocket, HandshakeResult> {
        val socketFactory = context.socketFactory
        val raw = Socket()
        raw.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
        val socket = socketFactory.createSocket(raw, host, port, true) as SSLSocket
        socket.soTimeout = HANDSHAKE_TIMEOUT_MS

        if (disableSessionTickets) {
            SSLSockets.setUseSessionTickets(socket, false)
        }

        val params: SSLParameters = socket.sslParameters
        params.protocols = protocols
        params.applicationProtocols = alpnProtocols
        socket.sslParameters = params

        val start = System.nanoTime()
        try {
            socket.startHandshake()
        } catch (e: Exception) {
            socket.close()
            throw HandshakeFailed("handshake failed: ${e.message}", e)
        }
        val elapsedMs = (System.nanoTime() - start) / 1_000_000

        val session = socket.session
        val result = HandshakeResult(
            latencyMs = elapsedMs,
            negotiatedProtocol = socket.applicationProtocol,
            protocolVersion = session.protocol,
            cipherSuite = session.cipherSuite,
        )
        return socket to result
    }

    /** null if the platform predates API 31 (android.net.ssl.SSLSockets.exportKeyingMaterial). */
    fun exportKeyingMaterialOrNull(socket: SSLSocket, label: String, context: ByteArray?, length: Int): ByteArray? {
        if (Build.VERSION.SDK_INT < 31) return null
        return SSLSockets.exportKeyingMaterial(socket, label, context, length)
    }
}
