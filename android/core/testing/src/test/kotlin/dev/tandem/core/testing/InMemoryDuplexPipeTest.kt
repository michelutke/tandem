package dev.tandem.core.testing

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Timeout
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

@Timeout(30, unit = TimeUnit.SECONDS)
class InMemoryDuplexPipeTest {
    @Test
    fun duplexPipe_writeOnA_sameBytesReadableOnB() {
        val pipe = InMemoryDuplexPipe()
        pipe.endpointA.output.write("hello tandem".toByteArray())

        val buffer = ByteArray(64)
        val n = pipe.endpointB.input.read(buffer)

        assertEquals("hello tandem", String(buffer, 0, n))
    }

    @Test
    fun duplexPipe_capacityFull_writerSuspendsUntilPeerReads() {
        val capacity = 64 * 1024
        val pipe = InMemoryDuplexPipe(capacity = capacity)
        val payload = ByteArray(1024 * 1024) { (it * 31).toByte() }

        val writer = thread { pipe.endpointA.output.write(payload) }
        while (pipe.capturedAToB().size < capacity) Thread.yield()
        Thread.sleep(50)
        assertEquals(capacity, pipe.capturedAToB().size, "writer must block once the buffer is full")

        val received = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        while (received.size() < payload.size) {
            val n = pipe.endpointB.input.read(buffer)
            received.write(buffer, 0, n)
        }
        writer.join()

        assertArrayEquals(payload, received.toByteArray())
    }

    @Test
    fun duplexPipe_closeAbruptly_peerReadThrowsIoException() =
        runBlocking {
            val pipe = InMemoryDuplexPipe(ioDispatcher = Dispatchers.IO)
            val pendingRead = async { runCatching { pipe.endpointB.read(ByteArray(16)) } }
            Thread.sleep(20)

            pipe.endpointA.closeAbruptly()

            val failure = pendingRead.await().exceptionOrNull()
            assertTrue(failure is IOException, "expected IOException, got $failure")
        }

    @Test
    fun duplexPipe_closeGracefully_peerReadReturnsEndOfStream() {
        val pipe = InMemoryDuplexPipe()
        pipe.endpointA.output.write(byteArrayOf(7))
        pipe.endpointA.closeGracefully()

        val buffer = ByteArray(4)
        assertEquals(1, pipe.endpointB.input.read(buffer))
        assertEquals(-1, pipe.endpointB.input.read(buffer))
    }

    @Test
    fun duplexPipe_capture_recordsBytesPerDirection() {
        val pipe = InMemoryDuplexPipe()
        pipe.endpointA.output.write(byteArrayOf(1, 2, 3))
        pipe.endpointB.output.write(byteArrayOf(9))
        pipe.injectTowardsB(byteArrayOf(4))

        assertArrayEquals(byteArrayOf(1, 2, 3, 4), pipe.capturedAToB())
        assertArrayEquals(byteArrayOf(9), pipe.capturedBToA())
    }
}
