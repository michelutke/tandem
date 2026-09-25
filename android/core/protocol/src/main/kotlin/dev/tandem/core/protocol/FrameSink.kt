package dev.tandem.core.protocol

/**
 * Minimal suspend write seam, symmetric with [FrameSource] (E11-02): `core/protocol` may not
 * depend on `core/transport`'s `ByteStream`, so callers (real code and tests alike) adapt
 * whatever they write to — a `ByteStream`/`InMemoryDuplexPipe` endpoint in tests, a real socket's
 * output elsewhere — with a lambda. [dev.tandem.core.protocol.multiplex.ChannelMultiplexer]
 * (E11-05) writes each [FrameEncoder]-encoded frame through this seam, one at a time.
 */
fun interface FrameSink {
    suspend fun write(bytes: ByteArray)
}
