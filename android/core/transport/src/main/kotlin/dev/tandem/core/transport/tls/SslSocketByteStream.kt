package dev.tandem.core.transport.tls

import dev.tandem.core.transport.ByteStream
import java.io.InputStream
import java.io.OutputStream
import javax.net.ssl.SSLSocket

/**
 * [ByteStream] over a connected, handshaken [SSLSocket] (E12-04). Carries frames only: per D-67
 * (SPEC.md, "Channel binding") this class exposes no channel-binding or exporter value of any
 * kind — no `channelBinding` property, no call to `SSLSockets.exportKeyingMaterial` anywhere in
 * this class or [SslClientFactory].
 */
class SslSocketByteStream(
    private val socket: SSLSocket,
) : ByteStream {
    override val input: InputStream = socket.inputStream
    override val output: OutputStream = socket.outputStream

    /** Orderly close: a plain `socket.close()` triggers a TLS `close_notify` under JSSE. Idempotent. */
    override fun closeGracefully() {
        if (socket.isClosed) return
        socket.close()
    }

    /** Abrupt teardown: force a hard TCP reset so the peer sees no clean `close_notify`/FIN. Idempotent. */
    override fun closeAbruptly() {
        if (socket.isClosed) return
        socket.setSoLinger(true, 0)
        socket.close()
    }
}
