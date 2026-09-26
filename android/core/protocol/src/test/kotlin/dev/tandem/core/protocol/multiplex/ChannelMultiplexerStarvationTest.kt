package dev.tandem.core.protocol.multiplex

import com.google.protobuf.ByteString
import dev.tandem.core.protocol.FrameSink
import dev.tandem.core.protocol.FrameSource
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.mediaTicketGrant
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.Random
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Duration.Companion.seconds

/**
 * Starvation regression test (E11-09; SPEC.md #channels-and-flow-control-credits, D-64): two real
 * [ChannelMultiplexer]/flow-control (E11-07) stacks, wired over [ThrottledFramePipe] rather than
 * `InMemoryDuplexPipe` (E00-19) — that pipe blocks real threads via `ReentrantLock`/`Condition`
 * (see [ChannelMultiplexerTest]'s doc comment), which cannot be driven deterministically by
 * `runTest`'s virtual scheduler. [ThrottledFramePipe] is built entirely from suspend functions,
 * mirroring [ChannelMultiplexerFlowControlTest]'s `FakeFramePipe`, but bounded at a 64 KiB
 * capacity per direction whose reader drains at a modelled 10 MiB/s (a `delay` proportional to
 * the bytes actually drained per read, advanced by the `runTest` scheduler, E00-18) — the issue's
 * bandwidth model, not a real link.
 *
 * `files.proto` (E40-01) — the real FILES chunk payload — is not implemented yet, so this test
 * carries its 256 KiB synthetic chunks in [dev.tandem.protocol.v1.MediaTicketGrant.ticket]: the
 * only payload type in the current protocol with an arbitrary-length `bytes` field.
 * [ChannelMultiplexer] never inspects payload semantics against `channel` (only that some payload
 * is set), so this is a test-only stand-in with no bearing on that message's real 32-byte
 * production use, confined to this file.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ChannelMultiplexerStarvationTest {
    @Test
    fun starvation_files50MiBSaturating_everyNotifyWithin50msVirtual() =
        runTest {
            val result = runStarvationScenario()
            result.notifyLatenciesMs.forEachIndexed { index, latencyMs ->
                assertTrue(
                    latencyMs <= NOTIFY_LATENCY_BOUND_MS,
                    "NOTIFY #$index took ${latencyMs}ms of virtual time while FILES saturated the " +
                        "link, expected <= ${NOTIFY_LATENCY_BOUND_MS}ms",
                )
            }
        }

    @Test
    fun starvation_files50MiBSaturating_allFilesBytesDeliveredInOrder() =
        runTest {
            val result = runStarvationScenario()
            assertEquals(
                FILES_CHUNK_COUNT,
                result.filesChunksReceived,
                "expected all $FILES_CHUNK_COUNT FILES chunks (50 MiB) delivered",
            )
            assertNull(
                result.filesMismatchIndex,
                "FILES chunk content diverged from what was sent at index ${result.filesMismatchIndex}",
            )
        }

    /**
     * Runs the shared scenario: [a] sends [FILES_CHUNK_COUNT] 256 KiB FILES chunks back-to-back
     * (paced only by E11-07's own credit/flow control and [ThrottledFramePipe]'s modelled
     * bandwidth) while also sending [NOTIFY_COUNT] NOTIFY frames every [NOTIFY_INTERVAL] of
     * virtual time; [b] continuously drains both inbound flows (consumption is what drives E11-07's
     * receive-side `CreditGrant` replenishment, SPEC.md D-64).
     */
    private suspend fun TestScope.runStarvationScenario(): ScenarioResult {
        val testScope = this
        val pipe = ThrottledFramePipe(LINK_CAPACITY_BYTES, LINK_BYTES_PER_SECOND)
        val a = ChannelMultiplexer(pipe.sourceA, pipe.sinkA)
        val b = ChannelMultiplexer(pipe.sourceB, pipe.sinkB)
        backgroundScope.launch { a.start() }
        backgroundScope.launch { b.start() }

        val notify = NotifyTimeline(NOTIFY_COUNT)
        val files = FilesTimeline(FILES_CHUNK_COUNT)
        backgroundScope.launch {
            b.inbound(Channel.CHANNEL_NOTIFY).collect { notify.recordReceive(testScope.currentTime) }
        }
        backgroundScope.launch {
            b.inbound(Channel.CHANNEL_FILES).collect { frame ->
                val ticket = frame.payload.mediaTicketGrant.ticket
                files.recordReceive(ticket.toByteArray())
            }
        }

        val filesJob = launch { sendFilesStream(a) }
        val notifyJob = launch { sendNotifyStream(a, notify, testScope) }

        withTimeout(SCENARIO_TIMEOUT) {
            filesJob.join()
            notifyJob.join()
            notify.done.await()
            files.done.await()
        }

        return ScenarioResult(notify.latenciesMs(), files.receivedCount, files.mismatchIndex)
    }

    private suspend fun sendFilesStream(a: ChannelMultiplexer) {
        repeat(FILES_CHUNK_COUNT) { index ->
            val chunk = filesChunk(index)
            a.send(Channel.CHANNEL_FILES) {
                mediaTicketGrant = mediaTicketGrant { ticket = ByteString.copyFrom(chunk) }
            }
        }
    }

    private suspend fun sendNotifyStream(
        a: ChannelMultiplexer,
        notify: NotifyTimeline,
        testScope: TestScope,
    ) {
        repeat(NOTIFY_COUNT) { index ->
            notify.recordSend(index, testScope.currentTime)
            a.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
            delay(NOTIFY_INTERVAL)
        }
    }

    private data class ScenarioResult(
        val notifyLatenciesMs: List<Long>,
        val filesChunksReceived: Int,
        val filesMismatchIndex: Int?,
    )

    /** Tracks each NOTIFY frame's send/receive virtual timestamp, indexed by send order. */
    private class NotifyTimeline(
        count: Int,
    ) {
        private val sendTimes = LongArray(count)
        private val receiveTimes = LongArray(count)
        private var receivedCount = 0
        val done = CompletableDeferred<Unit>()

        fun recordSend(
            index: Int,
            time: Long,
        ) {
            sendTimes[index] = time
        }

        fun recordReceive(time: Long) {
            receiveTimes[receivedCount] = time
            receivedCount++
            if (receivedCount == sendTimes.size) done.complete(Unit)
        }

        fun latenciesMs(): List<Long> = sendTimes.indices.map { receiveTimes[it] - sendTimes[it] }
    }

    /** Tracks FILES chunk arrival count and the first index whose content diverged from [filesChunk]. */
    private class FilesTimeline(
        private val expectedCount: Int,
    ) {
        var receivedCount = 0
            private set
        var mismatchIndex: Int? = null
            private set
        val done = CompletableDeferred<Unit>()

        fun recordReceive(actual: ByteArray) {
            if (mismatchIndex == null && !actual.contentEquals(filesChunk(receivedCount))) {
                mismatchIndex = receivedCount
            }
            receivedCount++
            if (receivedCount == expectedCount) done.complete(Unit)
        }
    }

    private companion object {
        const val NOTIFY_COUNT = 100
        const val FILES_CHUNK_COUNT = 200
        const val FILES_CHUNK_BYTES = 256 * 1024
        const val LINK_CAPACITY_BYTES = 64 * 1024
        const val LINK_BYTES_PER_SECOND = 10L * 1024 * 1024
        const val NOTIFY_LATENCY_BOUND_MS = 50L
        val NOTIFY_INTERVAL = 100.milliseconds
        val SCENARIO_TIMEOUT = 60.seconds

        /** Deterministic 256 KiB pattern for chunk [index]: regenerated on receipt to verify byte-identity. */
        fun filesChunk(index: Int): ByteArray =
            ByteArray(FILES_CHUNK_BYTES).also { Random(index.toLong()).nextBytes(it) }
    }

    /**
     * A bounded, throttled duplex pipe (E11-09): unlike `InMemoryDuplexPipe` (E00-19), this is
     * built entirely from suspend functions so a `runTest` virtual-time scheduler can drive it —
     * mirroring [ChannelMultiplexerFlowControlTest]'s `FakeFramePipe`. Each direction is a bounded
     * [capacityBytes] ring buffer; every [Direction.read] suspends a [bytesPerSecond]-proportional
     * `delay` after actually draining bytes, modelling a bandwidth-limited link rather than an
     * unlimited one.
     */
    private class ThrottledFramePipe(
        capacityBytes: Int,
        bytesPerSecond: Long,
    ) {
        private val aToB = Direction(capacityBytes, bytesPerSecond)
        private val bToA = Direction(capacityBytes, bytesPerSecond)

        val sourceA: FrameSource = FrameSource { buffer, offset, length -> bToA.read(buffer, offset, length) }
        val sinkA: FrameSink = FrameSink { bytes -> aToB.write(bytes, 0, bytes.size) }
        val sourceB: FrameSource = FrameSource { buffer, offset, length -> aToB.read(buffer, offset, length) }
        val sinkB: FrameSink = FrameSink { bytes -> bToA.write(bytes, 0, bytes.size) }

        /**
         * One direction's bounded ring buffer, guarded by [mutex]. [write] and [read] each check
         * their condition and register a waiter atomically under a single lock acquisition (like
         * [ChannelMultiplexer.FlowControl.awaitSendCredit]), so a wakeup between check and
         * registration can never be lost.
         */
        private class Direction(
            private val capacity: Int,
            private val bytesPerSecond: Long,
        ) {
            private val mutex = Mutex()
            private val ring = ByteArray(capacity)
            private var head = 0
            private var size = 0
            private val notEmptyWaiters = mutableListOf<CompletableDeferred<Unit>>()
            private val notFullWaiters = mutableListOf<CompletableDeferred<Unit>>()

            suspend fun write(
                b: ByteArray,
                off: Int,
                len: Int,
            ) {
                var written = 0
                while (written < len) {
                    val waiter =
                        mutex.withLock {
                            if (size == capacity) {
                                CompletableDeferred<Unit>().also { notFullWaiters += it }
                            } else {
                                val chunk = minOf(len - written, capacity - size)
                                for (i in 0 until chunk) ring[(head + size + i) % capacity] = b[off + written + i]
                                size += chunk
                                written += chunk
                                wake(notEmptyWaiters)
                                null
                            }
                        }
                    waiter?.await()
                }
            }

            suspend fun read(
                b: ByteArray,
                off: Int,
                len: Int,
            ): Int {
                if (len == 0) return 0
                while (true) {
                    var readCount = 0
                    val waiter =
                        mutex.withLock {
                            if (size > 0) {
                                val chunk = minOf(len, size)
                                for (i in 0 until chunk) b[off + i] = ring[(head + i) % capacity]
                                head = (head + chunk) % capacity
                                size -= chunk
                                readCount = chunk
                                wake(notFullWaiters)
                                null
                            } else {
                                CompletableDeferred<Unit>().also { notEmptyWaiters += it }
                            }
                        }
                    if (waiter == null) {
                        delay(durationFor(readCount))
                        return readCount
                    }
                    waiter.await()
                }
            }

            private fun durationFor(bytes: Int): Duration =
                (bytes.toLong() * NANOS_PER_SECOND / bytesPerSecond).nanoseconds

            private fun wake(waiters: MutableList<CompletableDeferred<Unit>>) {
                val current = waiters.toList()
                waiters.clear()
                current.forEach { it.complete(Unit) }
            }

            private companion object {
                const val NANOS_PER_SECOND = 1_000_000_000L
            }
        }
    }
}
