package dev.tandem.core.transport.tls

import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509KeyManager
import javax.net.ssl.X509TrustManager

/** The single ALPN identifier this protocol's client ever offers (SPEC.md, "TLS version and cipher profile"). */
const val TANDEM_ALPN_PROTOCOL = "tandem/1"

/** Thrown when the peer completes the TLS handshake but does not select [TANDEM_ALPN_PROTOCOL]. */
class AlpnMismatchException(
    message: String,
) : SSLHandshakeException(message)

/**
 * Builds the phone's TLS 1.3-only client connection (E12-04). A fresh [SSLContext] is created per
 * connection with no shared client session cache, so the client never offers a PSK identity on a
 * subsequent connection (SPEC.md, cycle 4). [keyManager] presents the app's client certificate
 * (E12-06, always `IdentityKeyManager` in production); [trustManager] decides whether to accept
 * the peer's certificate (E12-05, not yet implemented — injected here so this class never contains
 * pin-checking logic itself).
 *
 * Socket creation and the network handshake are split into [createSocket] and [connect] so a
 * `unit:` test can assert the created socket's TLS configuration (`enabledProtocols`, ALPN) with
 * no network involved at all.
 */
class SslClientFactory(
    private val keyManager: X509KeyManager,
    private val trustManager: X509TrustManager,
    private val sessionTicketDisabler: SessionTicketDisabler = AndroidSessionTicketDisabler(),
) {
    /**
     * Creates an unconnected [SSLSocket] configured for this protocol's TLS profile: TLS 1.3 only,
     * ALPN restricted to [TANDEM_ALPN_PROTOCOL], and session tickets disabled. No network I/O
     * happens here.
     */
    fun createSocket(): SSLSocket {
        val context = SSLContext.getInstance("TLSv1.3")
        context.init(arrayOf(keyManager), arrayOf(trustManager), null)

        val socket = context.socketFactory.createSocket() as SSLSocket
        socket.enabledProtocols = arrayOf("TLSv1.3")

        val parameters = socket.sslParameters
        parameters.applicationProtocols = arrayOf(TANDEM_ALPN_PROTOCOL)
        socket.sslParameters = parameters

        sessionTicketDisabler.disable(socket)
        return socket
    }

    /**
     * Connects [socket] to [address] by literal IP (no SNI, per SPEC.md) and runs the TLS 1.3
     * handshake, then wraps the connected socket as a [dev.tandem.core.transport.ByteStream]. The
     * hostname on [address], if any, is stripped before dialing (`InetAddress.getByAddress`), so a
     * caller passing a hostname-bearing address (e.g. from `InetAddress.getByName`) can never make
     * Conscrypt emit a `server_name` extension.
     *
     * `SSLParameters.setApplicationProtocols` only declares what this client offers; it does not,
     * by itself, make the underlying TLS stack fail a handshake whose peer selected a different
     * (or no) protocol — mirroring the explicit ALPN check SPEC.md requires on the macOS listener
     * side, this method verifies the negotiated protocol itself and fails closed if it isn't
     * exactly [TANDEM_ALPN_PROTOCOL].
     *
     * [handshakeTimeoutMillis] is applied as `socket.soTimeout` around `startHandshake()` only (SPEC.md
     * §10 assigns the phone's 10 s TLS handshake deadline; this is the seam that deadline is enforced
     * through, since a blocking `startHandshake()` cannot otherwise be unblocked). On any failure —
     * connect, handshake, or ALPN mismatch — [socket] is closed before the exception propagates.
     */
    fun connect(
        socket: SSLSocket,
        address: InetAddress,
        port: Int,
        connectTimeoutMillis: Int = DEFAULT_CONNECT_TIMEOUT_MILLIS,
        handshakeTimeoutMillis: Int = DEFAULT_HANDSHAKE_TIMEOUT_MILLIS,
    ): SslSocketByteStream {
        try {
            val noSniAddress = InetSocketAddress(InetAddress.getByAddress(address.address), port)
            socket.connect(noSniAddress, connectTimeoutMillis)

            socket.soTimeout = handshakeTimeoutMillis
            socket.startHandshake()
            socket.soTimeout = 0

            if (socket.applicationProtocol != TANDEM_ALPN_PROTOCOL) {
                val negotiated = socket.applicationProtocol
                throw AlpnMismatchException(
                    "Server did not select ALPN protocol \"$TANDEM_ALPN_PROTOCOL\" (negotiated: \"$negotiated\")",
                )
            }
        } catch (e: IOException) {
            runCatching { socket.close() }
            throw e
        }

        return SslSocketByteStream(socket)
    }

    private companion object {
        /** SPEC.md §10 / E12-08: the phone's TLS handshake deadline when dialing. */
        const val DEFAULT_HANDSHAKE_TIMEOUT_MILLIS = 10_000

        // D-68: 3 s per-address dial timeout.
        const val DEFAULT_CONNECT_TIMEOUT_MILLIS = 3_000
    }
}
