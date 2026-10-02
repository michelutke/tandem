package dev.tandem.feature.messaging

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsSyncStatus
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.smsMessage
import dev.tandem.protocol.v1.smsSyncRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** SmsSyncSession tests (E50-13; `docs/planning/backlog/phase-5.yaml` E50-13's `tdd:` list). */
@OptIn(ExperimentalCoroutinesApi::class)
class SmsSyncSessionTest {
    @Test
    fun smsSyncSession_freshRequestOnFiveThousandRows_sends25PagesNewestFirst() =
        runTest {
            val inner = FakeTandemSession()

            syncSession(FakeSmsSource(messages(5000)), inner).handle(request())

            val pages = inner.sentFrames.map { it.smsSyncResponse }
            assertEquals(25, pages.size)
            assertTrue(pages.all { it.messagesCount <= 200 })
            assertEquals((5000L downTo 4801L).toList(), pages.first().messagesList.map { it.id })
            assertEquals(listOf(true), pages.map { it.backfillComplete }.distinct().filter { it })
            assertTrue(pages.last().backfillComplete)
            assertFalse(pages[23].backfillComplete)
            assertTrue(pages.all { it.highWatermarkId == 5000L })
            assertEquals(SmsSyncStatus.SMS_SYNC_STATUS_OK, pages.first().status)
        }

    @Test
    fun smsSyncSession_reconnectWithMacCursors_unionEqualsFixtureWithoutGaps() =
        runTest {
            val source = FakeSmsSource(messages(5000))
            val first = FakeTandemSession()
            val job = launch { syncSession(source, PageLimitedSession(first, limit = 7)).handle(request()) }
            runCurrent()
            job.cancel()
            val delivered = first.sentFrames.map { it.smsSyncResponse }
            assertEquals(7, delivered.size)
            val last = delivered.last()

            val second = FakeTandemSession()
            syncSession(source, second).handle(
                request(sinceId = last.highWatermarkId, backfillBeforeId = last.backfillCursorId),
            )

            val resumed = second.sentFrames.map { it.smsSyncResponse }
            val ids = (delivered + resumed).flatMap { r -> r.messagesList.map { it.id } }
            assertEquals((1L..5000L).toSet(), ids.toSet())
            assertTrue(ids.size - ids.toSet().size <= 200)
            assertTrue(
                second.sentFrames
                    .last()
                    .smsSyncResponse.backfillComplete,
            )
        }

    @Test
    fun smsSyncSession_zeroChannelCredits_sendsNoFurtherFrame() =
        runTest {
            val inner = FakeTandemSession()
            val credits = Semaphore(permits = 2, acquiredPermits = 2)
            val sync = syncSession(FakeSmsSource(messages(5)), CreditGatedSession(inner, credits))

            val job = launch { sync.handle(request(pageSize = 2)) }
            runCurrent()
            assertEquals(0, inner.sentFrames.size)

            credits.release()
            runCurrent()
            assertEquals(1, inner.sentFrames.size)
            assertTrue(job.isActive)

            credits.release()
            credits.release()
            runCurrent()
            assertEquals(3, inner.sentFrames.size)
            assertTrue(
                inner.sentFrames
                    .last()
                    .smsSyncResponse.backfillComplete,
            )
        }

    @Test
    fun smsSyncSession_sinceIdBelowMax_sendsForwardRowsBeforeBackfill() =
        runTest {
            val inner = FakeTandemSession()

            syncSession(FakeSmsSource(messages(5000)), inner)
                .handle(request(sinceId = 4990, backfillBeforeId = 4801))

            val pages = inner.sentFrames.map { it.smsSyncResponse }
            assertEquals((4991L..5000L).toList(), pages.first().messagesList.map { it.id })
            assertFalse(pages.first().backfillComplete)
            assertEquals(5000L, pages.first().highWatermarkId)
            assertEquals(4800L, pages[1].messagesList.first().id)
        }

    @Test
    fun smsSyncSession_readSmsRevoked_respondsPermissionRequiredWithoutRows() =
        runTest {
            val inner = FakeTandemSession()

            syncSession(FakeSmsSource(messages(3), readPermitted = false), inner).handle(request())

            val frame = inner.sentFrames.single()
            assertEquals(Channel.CHANNEL_SMS, frame.channel)
            assertEquals(SmsSyncStatus.SMS_SYNC_STATUS_PERMISSION_REQUIRED, frame.smsSyncResponse.status)
            assertEquals(0, frame.smsSyncResponse.messagesCount)
            assertEquals(0, frame.smsSyncResponse.threadsCount)
        }

    @Test
    fun smsSyncSession_fullSync_logLinesContainNoBodyOrAddress() =
        runTest {
            val inner = FakeTandemSession()
            val lines = mutableListOf<String>()

            syncSession(FakeSmsSource(messages(450)), inner, log = { lines += it }).handle(request())

            assertTrue(lines.isNotEmpty())
            assertTrue(lines.none { it.contains("secret body") || it.contains("+41790000000") })
        }

    @Test
    fun smsSyncSession_secondRequestWhileInFlight_firstStopsAfterCurrentPage() =
        runTest {
            val inner = FakeTandemSession()
            val credits = Semaphore(permits = 10, acquiredPermits = 10)
            val source = FakeSmsSource(messages(1000))
            val sync = syncSession(source, CreditGatedSession(inner, credits))
            val job = launch { sync.run() }
            runCurrent()

            inner.emitIncoming(smsEnvelope(request(pageSize = 100)))
            runCurrent()
            inner.emitIncoming(smsEnvelope(request(sinceId = 1000, pageSize = 100)))
            runCurrent()
            repeat(10) { credits.release() }
            runCurrent()

            val pages = inner.sentFrames.map { it.smsSyncResponse }
            assertEquals(listOf(100, 0), pages.map { it.messagesCount })
            assertEquals(
                1000L,
                pages
                    .first()
                    .messagesList
                    .first()
                    .id,
            )
            job.cancel()
        }

    private fun TestScope.syncSession(
        source: SmsSource,
        session: TandemSession,
        log: (String) -> Unit = {},
    ) = SmsSyncSession(source, session, StandardTestDispatcher(testScheduler), log)

    private fun request(
        sinceId: Long = 0,
        backfillBeforeId: Long = 0,
        pageSize: Int = 0,
    ) = smsSyncRequest {
        this.sinceId = sinceId
        this.backfillBeforeId = backfillBeforeId
        this.pageSize = pageSize
    }

    private fun smsEnvelope(request: dev.tandem.protocol.v1.SmsSyncRequest) =
        envelope {
            channel = Channel.CHANNEL_SMS
            smsSyncRequest = request
        }

    private fun messages(count: Int): List<SmsMessage> =
        (1..count).map {
            smsMessage {
                id = it.toLong()
                address = "+41790000000"
                body = "secret body $it"
            }
        }

    private class CreditGatedSession(
        private val inner: FakeTandemSession,
        private val credits: Semaphore,
    ) : TandemSession by inner {
        override suspend fun send(
            channel: Channel,
            payload: EnvelopeKt.Dsl.() -> Unit,
        ) {
            credits.acquire()
            inner.send(channel, payload)
        }
    }

    private class PageLimitedSession(
        private val inner: FakeTandemSession,
        private val limit: Int,
    ) : TandemSession by inner {
        private var sent = 0

        override suspend fun send(
            channel: Channel,
            payload: EnvelopeKt.Dsl.() -> Unit,
        ) {
            if (sent == limit) kotlinx.coroutines.awaitCancellation()
            sent++
            inner.send(channel, payload)
        }
    }
}
