package dev.tandem.feature.messaging

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.smsMessage
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** SmsIncrementalSync tests (E50-03; `docs/planning/backlog/phase-5.yaml` E50-03's `tdd:` list). */
@OptIn(ExperimentalCoroutinesApi::class)
class SmsIncrementalSyncTest {
    @Test
    fun incrementalSync_singleInsertedRow_pushesExactlyThatRow() =
        runTest {
            val source = FakeSmsSource(messages(5))
            val session = FakeTandemSession()
            val job = start(source, session) { 5 }

            source.messages += row(6)
            source.emitChange()
            advanceTimeBy(DEBOUNCE_MS + 1)
            runCurrent()

            val pushed = session.sentFrames.map { it.smsSyncResponse }
            assertEquals(1, pushed.size)
            assertEquals(listOf(6L), pushed.single().messagesList.map { it.id })
            assertEquals(6L, pushed.single().highWatermarkId)
            job.cancel()
        }

    @Test
    fun incrementalSync_fiveCallbacksWithin250ms_singleQueryAndPush() =
        runTest {
            val source = CountingSource(FakeSmsSource(messages(5)))
            val session = FakeTandemSession()
            val job = start(source, session) { 5 }

            source.inner.messages += row(6)
            repeat(5) {
                source.inner.emitChange()
                advanceTimeBy(40)
            }
            advanceTimeBy(DEBOUNCE_MS)
            runCurrent()
            assertEquals(1, session.sentFrames.size)
            assertEquals(2, source.newerThanCalls)

            source.inner.emitChange()
            advanceTimeBy(DEBOUNCE_MS + 1)
            runCurrent()
            assertEquals(1, session.sentFrames.size)
            job.cancel()
        }

    @Test
    fun incrementalSync_rowInsertedDuringSnapshot_deliveredExactlyOnce() =
        runTest {
            val source = FakeSmsSource(messages(5))
            val session = FakeTandemSession()
            val job =
                start(source, session) {
                    val snapshotMax = source.maxId()
                    source.messages += row(6)
                    snapshotMax
                }

            source.emitChange()
            source.emitChange()
            advanceTimeBy(DEBOUNCE_MS + 1)
            runCurrent()
            source.emitChange()
            advanceTimeBy(DEBOUNCE_MS + 1)
            runCurrent()

            val ids = session.sentFrames.flatMap { it.smsSyncResponse.messagesList.map { m -> m.id } }
            assertEquals(listOf(6L), ids)
            job.cancel()
        }

    @Test
    fun incrementalSync_newSessionAfterProcessRestart_pushesOnlyRowsAboveSinceId() =
        runTest {
            val source = FakeSmsSource(messages(10))
            val session = FakeTandemSession()
            val job = start(source, session) { 7 }

            source.emitChange()
            advanceTimeBy(DEBOUNCE_MS + 1)
            runCurrent()

            val ids = session.sentFrames.flatMap { it.smsSyncResponse.messagesList.map { m -> m.id } }
            assertEquals(listOf(8L, 9L, 10L), ids)
            job.cancel()
        }

    @Test
    fun incrementalSync_sessionClosed_noFurtherProviderQuery() =
        runTest {
            val source = CountingSource(FakeSmsSource(messages(5)))
            val session = FakeTandemSession()
            val job = start(source, session) { 5 }
            runCurrent()

            job.cancel()
            source.inner.messages += row(6)
            source.inner.emitChange()
            advanceTimeBy(DEBOUNCE_MS * 2)
            runCurrent()

            assertEquals(0, source.newerThanCalls)
            assertEquals(0, session.sentFrames.size)
        }

    private fun TestScope.start(
        source: SmsSource,
        session: FakeTandemSession,
        initialLastSentId: suspend () -> Long,
    ) = launch {
        SmsIncrementalSync(source, session, StandardTestDispatcher(testScheduler)).run(initialLastSentId)
    }.also { runCurrent() }

    private fun messages(count: Int): List<SmsMessage> = (1..count).map { row(it.toLong()) }

    private fun row(id: Long): SmsMessage =
        smsMessage {
            this.id = id
            address = "+41790000000"
            body = "secret body $id"
        }

    private class CountingSource(
        val inner: FakeSmsSource,
    ) : SmsSource by inner {
        var newerThanCalls = 0

        override fun newerThan(
            sinceId: Long,
            limit: Int,
        ): List<SmsMessage> {
            newerThanCalls++
            return inner.newerThan(sinceId, limit)
        }
    }

    private companion object {
        const val DEBOUNCE_MS = SmsIncrementalSync.DEBOUNCE_MS
    }
}
