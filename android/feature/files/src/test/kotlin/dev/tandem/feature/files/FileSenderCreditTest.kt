package dev.tandem.feature.files

import dev.tandem.core.protocol.DecodeResult
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.core.protocol.FrameSink
import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.protocol.flowcontrol.CreditCaps
import dev.tandem.core.protocol.multiplex.ChannelMultiplexer
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.creditGrant
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.fileAccept
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.channels.Channel as KtChannel

// E40-03 tdd (docs/planning/backlog/phase-4.yaml): the real E11-07 ChannelMultiplexer credit
// ledger gates the sender. The pipe is suspend-based (as in ChannelMultiplexerFlowControlTest)
// because InMemoryDuplexPipe blocks real threads, which runTest's virtual clock cannot drive.
@OptIn(ExperimentalCoroutinesApi::class)
class FileSenderCreditTest {
    @TempDir
    lateinit var dir: File

    @Test
    fun androidSender_zeroFilesCredits_noChunkUntilGrant() =
        runTest {
            val toPhone = KtChannel<Byte>(KtChannel.UNLIMITED)
            val toMac = KtChannel<Byte>(KtChannel.UNLIMITED)
            val mux = ChannelMultiplexer(sourceOver(toPhone), sinkOver(toMac))
            backgroundScope.launch { mux.start() }
            val dispatcher = StandardTestDispatcher(testScheduler)
            val session = MultiplexerSession(mux)
            val file = File(dir, "big").also { it.writeBytes(ByteArray(CHUNKS_IN_FILE * CHUNK)) }
            FileSender(session, FilesScheduler(session, dispatcher), { File(it).inputStream() }, dispatcher, dispatcher)
                .send(SendRequest("t1", file.path, "big.bin", "application/octet-stream"))
            runCurrent()
            sinkOver(toPhone).write(frame(Channel.CHANNEL_FILES, 1) { fileAccept = fileAccept { id = "t1" } })
            advanceTimeBy(5.seconds)

            val initial = macFrames(toMac)
            assertEquals(CreditCaps.PROTOCOL_MAX, initial.count { it.channel == Channel.CHANNEL_FILES })

            sinkOver(toPhone).write(
                frame(Channel.CHANNEL_CONTROL, 2) {
                    creditGrant =
                        creditGrant {
                            this.channel = Channel.CHANNEL_FILES
                            amount = 3
                        }
                },
            )
            advanceTimeBy(5.seconds)

            val released = macFrames(toMac).filter { it.channel == Channel.CHANNEL_FILES }
            assertEquals(3, released.size)
            assertEquals(true, released.all { it.hasFileChunk() })
        }

    private fun macFrames(wire: KtChannel<Byte>): List<Envelope> {
        val bytes = ArrayList<Byte>()
        while (true) bytes += wire.tryReceive().getOrNull() ?: break
        var offset = 0
        val source =
            FrameSource { buffer, off, len ->
                if (offset >= bytes.size) {
                    -1
                } else {
                    val n = minOf(len, bytes.size - offset)
                    for (i in 0 until n) buffer[off + i] = bytes[offset + i]
                    offset += n
                    n
                }
            }
        val frames = mutableListOf<Envelope>()
        while (true) {
            val result = kotlinx.coroutines.runBlocking { FrameDecoder.decodeFrame(source) }
            if (result !is DecodeResult.Frame) return frames
            frames += result.envelope
        }
    }

    private fun frame(
        channel: Channel,
        seq: Long,
        payload: EnvelopeKt.Dsl.() -> Unit,
    ): ByteArray =
        FrameEncoder.encodeFrame(
            envelope {
                payload()
                this.channel = channel
                this.seq = seq
            },
        )

    private fun sourceOver(wire: KtChannel<Byte>): FrameSource =
        FrameSource { buffer, offset, length ->
            buffer[offset] = wire.receive()
            var n = 1
            while (n < length) {
                val next = wire.tryReceive()
                if (next.isFailure) break
                buffer[offset + n] = next.getOrThrow()
                n++
            }
            n
        }

    private fun sinkOver(wire: KtChannel<Byte>): FrameSink = FrameSink { bytes -> bytes.forEach { wire.send(it) } }

    private class MultiplexerSession(
        private val mux: ChannelMultiplexer,
    ) : TandemSession {
        override val state: StateFlow<ConnectionState> = MutableStateFlow(ConnectionState.Disconnected())

        override suspend fun send(
            channel: Channel,
            payload: EnvelopeKt.Dsl.() -> Unit,
        ) = mux.send(channel, payload)

        override fun receive(channel: Channel): Flow<Envelope> = mux.inbound(channel).map { it.payload }

        override fun close() = Unit
    }

    private companion object {
        const val CHUNK = 262_144
        const val CHUNKS_IN_FILE = 100
    }
}
