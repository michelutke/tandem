package dev.tandem.core.protocol

/**
 * Minimal suspend read seam for [FrameDecoder] (E11-02). `core/protocol` may not depend on
 * `core/transport` (whose `ByteStream` is the real seam, E00-19), so this is a small local
 * abstraction: callers (real code and tests alike) adapt whatever they read from — a
 * `ByteStream`/`InMemoryDuplexPipe` endpoint in tests, a real socket's input elsewhere — with a
 * lambda. Contract mirrors `InputStream.read(ByteArray)`: fills as many of [buffer]'s bytes as
 * are currently available, suspending until at least one byte arrives, and returns the count
 * read, or -1 at end of stream. Never returns 0 for a non-empty [buffer].
 */
fun interface FrameSource {
    suspend fun read(buffer: ByteArray): Int
}
