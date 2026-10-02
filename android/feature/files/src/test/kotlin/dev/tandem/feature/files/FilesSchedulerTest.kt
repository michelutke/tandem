package dev.tandem.feature.files

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.ThumbResult
import dev.tandem.protocol.v1.fileComplete
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

// E40-03 tdd (docs/planning/backlog/phase-4.yaml).
@OptIn(ExperimentalCoroutinesApi::class)
class FilesSchedulerTest {
    @Test
    fun androidFilesScheduler_transferInFlight_thumbResultSentWithinOneChunk() =
        runTest {
            val session = FakeTandemSession()
            val scheduler = FilesScheduler(session, StandardTestDispatcher(testScheduler))
            var sent = 0
            val stream =
                FrameStream {
                    if (sent == 1) launch { scheduler.sendPriority { thumbResult = ThumbResult.getDefaultInstance() } }
                    session.send(Channel.CHANNEL_FILES) { fileComplete = fileComplete { id = "c${sent++}" } }
                    yield()
                    sent < 4
                }
            launch { scheduler.run(stream) }
            runCurrent()

            val kinds = session.sentFrames.map { if (it.hasThumbResult()) "thumb" else "chunk" }
            assertEquals(listOf("chunk", "chunk", "thumb", "chunk", "chunk"), kinds)
        }
}
