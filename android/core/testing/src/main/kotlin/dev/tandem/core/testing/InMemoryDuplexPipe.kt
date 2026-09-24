package dev.tandem.core.testing

import dev.tandem.core.transport.ByteStream
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Two connected in-memory [ByteStream] endpoints (E00-19). Each direction is a bounded buffer of
 * [capacity] bytes, so a writer blocks until the peer reads (backpressure). Every byte that
 * crosses a direction is captured for "no application bytes before Ready" assertions.
 */
class InMemoryDuplexPipe(
    capacity: Int = DEFAULT_CAPACITY_BYTES,
    ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private val aToB = Direction(capacity)
    private val bToA = Direction(capacity)

    val endpointA: Endpoint = Endpoint(outgoing = aToB, incoming = bToA, ioDispatcher = ioDispatcher)
    val endpointB: Endpoint = Endpoint(outgoing = bToA, incoming = aToB, ioDispatcher = ioDispatcher)

    /** Bytes written from A to B so far (including injected ones). */
    fun capturedAToB(): ByteArray = aToB.captured()

    /** Bytes written from B to A so far (including injected ones). */
    fun capturedBToA(): ByteArray = bToA.captured()

    /** Writes raw bytes towards B as if A had sent them, e.g. malformed frames. */
    fun injectTowardsB(bytes: ByteArray) = aToB.write(bytes, 0, bytes.size)

    /** Writes raw bytes towards A as if B had sent them. */
    fun injectTowardsA(bytes: ByteArray) = bToA.write(bytes, 0, bytes.size)

    private companion object {
        const val DEFAULT_CAPACITY_BYTES = 64 * 1024
        const val BYTE_MASK = 0xFF
        const val END_OF_STREAM = -1
    }

    class Endpoint internal constructor(
        private val outgoing: Direction,
        private val incoming: Direction,
        private val ioDispatcher: CoroutineDispatcher,
    ) : ByteStream {
        override val input: InputStream =
            object : InputStream() {
                override fun read(): Int {
                    val one = ByteArray(1)
                    return if (read(one, 0, 1) == -1) -1 else one[0].toInt() and BYTE_MASK
                }

                override fun read(
                    b: ByteArray,
                    off: Int,
                    len: Int,
                ): Int = incoming.read(b, off, len)
            }

        override val output: OutputStream =
            object : OutputStream() {
                override fun write(b: Int) = write(byteArrayOf(b.toByte()), 0, 1)

                override fun write(
                    b: ByteArray,
                    off: Int,
                    len: Int,
                ) = outgoing.write(b, off, len)
            }

        /** Coroutine view: suspends (on the injected dispatcher) until bytes arrive; -1 on EOF. */
        suspend fun read(buffer: ByteArray): Int = runInterruptible(ioDispatcher) { input.read(buffer, 0, buffer.size) }

        /** Coroutine view: suspends while the peer's buffer is full. */
        suspend fun write(bytes: ByteArray) = runInterruptible(ioDispatcher) { output.write(bytes) }

        override fun closeGracefully() = outgoing.closeGracefully()

        override fun closeAbruptly() {
            outgoing.closeAbruptly()
            incoming.closeAbruptly()
        }
    }

    internal class Direction(
        private val capacity: Int,
    ) {
        private enum class State { OPEN, GRACEFUL, ABRUPT }

        private val lock = ReentrantLock()
        private val notEmpty = lock.newCondition()
        private val notFull = lock.newCondition()
        private val ring = ByteArray(capacity)
        private var head = 0
        private var size = 0
        private var state = State.OPEN
        private val capture = ByteArrayOutputStream()

        init {
            require(capacity > 0) { "capacity must be positive" }
        }

        fun write(
            b: ByteArray,
            off: Int,
            len: Int,
        ) {
            var written = 0
            lock.withLock {
                while (written < len) {
                    when (state) {
                        State.ABRUPT -> throw IOException("connection reset")
                        State.GRACEFUL -> throw IOException("write after close")
                        State.OPEN -> Unit
                    }
                    if (size == capacity) {
                        notFull.await()
                        continue
                    }
                    val chunk = minOf(len - written, capacity - size)
                    for (i in 0 until chunk) ring[(head + size + i) % capacity] = b[off + written + i]
                    capture.write(b, off + written, chunk)
                    size += chunk
                    written += chunk
                    notEmpty.signalAll()
                }
            }
        }

        fun read(
            b: ByteArray,
            off: Int,
            len: Int,
        ): Int {
            if (len == 0) return 0
            lock.withLock {
                while (size == 0 && state == State.OPEN) notEmpty.await()
                if (state == State.ABRUPT) throw IOException("connection reset")
                return if (size == 0) END_OF_STREAM else drainInto(b, off, len)
            }
        }

        /** Caller holds [lock] and [size] > 0. */
        private fun drainInto(
            b: ByteArray,
            off: Int,
            len: Int,
        ): Int {
            val chunk = minOf(len, size)
            for (i in 0 until chunk) b[off + i] = ring[(head + i) % capacity]
            head = (head + chunk) % capacity
            size -= chunk
            notFull.signalAll()
            return chunk
        }

        fun closeGracefully() =
            lock.withLock {
                if (state == State.OPEN) state = State.GRACEFUL
                notEmpty.signalAll()
                notFull.signalAll()
            }

        fun closeAbruptly() =
            lock.withLock {
                state = State.ABRUPT
                notEmpty.signalAll()
                notFull.signalAll()
            }

        fun captured(): ByteArray = lock.withLock { capture.toByteArray() }
    }
}
