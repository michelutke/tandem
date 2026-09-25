package dev.tandem.core.transport

import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream

/**
 * A bidirectional byte stream (E00-19): the seam every layer above the socket is written against.
 * The SSLSocket session (E12-04) implements it for real traffic; tests use `InMemoryDuplexPipe`
 * from `core/testing`, so no unit test ever opens a socket.
 */
interface ByteStream : Closeable {
    val input: InputStream
    val output: OutputStream

    /**
     * Orderly close of this end's sending direction (FIN / TLS close_notify): the peer reads EOF.
     * Reads on this end after calling this are undefined: `InMemoryDuplexPipe`'s fake only closes
     * the outgoing direction and leaves incoming readable, but a real TLS stream (E12-04) has no
     * half-close and fully closes the socket, so a consumer that reads after this call can pass
     * against the fake and fail against the real stream.
     */
    fun closeGracefully()

    /** Abrupt teardown (RST-like): the peer's reads and writes fail with an `IOException`. */
    fun closeAbruptly()

    override fun close() = closeAbruptly()
}
