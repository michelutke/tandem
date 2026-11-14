package dev.tandem.feature.files

import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream

@OptIn(ExperimentalCoroutinesApi::class)
class LiveFileSessionTest {
    @Test
    fun liveFileSession_sessionScopeAlreadyCancelled_onFinishedStillCalledOnceAndFeedsFailed() =
        runTest {
            val session = FakeTandemSession()
            val dispatcher = StandardTestDispatcher(testScheduler)
            val sender =
                FileSender(
                    session,
                    FilesScheduler(session, dispatcher),
                    { ByteArrayInputStream(ByteArray(3)) },
                    dispatcher,
                    dispatcher,
                )
            LiveFileSession.attach(sender, CoroutineScope(Job().apply { cancel() } + dispatcher))
            val finished = mutableListOf<SendRequest>()
            val feedback = mutableListOf<SendFeedback>()
            val request = SendRequest("id-1", "content://example/1", "a.txt", "text/plain")

            LiveFileSession.starter({ finished += it }) { feedback += it }.start(request)
            runCurrent()
            LiveFileSession.detach(sender)

            assertEquals(listOf(request), finished)
            assertEquals(listOf(SendFeedback.STARTED, SendFeedback.FAILED), feedback)
        }
}
