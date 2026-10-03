package dev.tandem.feature.messaging

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsSyncRequest
import dev.tandem.protocol.v1.SmsSyncStatus
import dev.tandem.protocol.v1.smsSyncResponse
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * E50-13 phone side of the SMS channel sync (PRD F-8.1, docs/protocol/SPEC.md #cursors): answers
 * each `SmsSyncRequest` with `SmsSyncResponse` pages read from [source] on [ioDispatcher]. The
 * Mac owns the cursors; this class keeps no state across requests. Pages are read and sent one
 * at a time; [TandemSession.send] suspends while the SMS channel has no send credit. [log]
 * receives counts and ids only, never message bodies or addresses (invariant 7).
 */
class SmsSyncSession(
    private val source: SmsSource,
    private val session: TandemSession,
    private val ioDispatcher: CoroutineDispatcher,
    private val log: (String) -> Unit = {},
) {
    /** Handles every `SmsSyncRequest` on the SMS channel; a new request supersedes the in-flight one. */
    suspend fun run() {
        coroutineScope {
            var previous: Job? = null
            var previousToken: SyncToken? = null
            session
                .receive(Channel.CHANNEL_SMS)
                .filter { it.hasSmsSyncRequest() }
                .collect { envelope ->
                    previousToken?.superseded = true
                    val token = SyncToken()
                    val predecessor = previous
                    previousToken = token
                    previous =
                        launch {
                            predecessor?.join()
                            handle(envelope.smsSyncRequest, token)
                        }
                }
        }
    }

    suspend fun handle(
        request: SmsSyncRequest,
        token: SyncToken = SyncToken(),
    ) {
        try {
            sync(request, token)
        } catch (_: SmsPermissionMissing) {
            log("sms sync: READ_SMS missing")
            session.send(Channel.CHANNEL_SMS) {
                smsSyncResponse =
                    smsSyncResponse {
                        status = SmsSyncStatus.SMS_SYNC_STATUS_PERMISSION_REQUIRED
                    }
            }
        }
    }

    private suspend fun sync(
        request: SmsSyncRequest,
        token: SyncToken,
    ) {
        val pageSize = if (request.pageSize > 0) request.pageSize else SmsSource.PAGE_SIZE
        val maxId = withContext(ioDispatcher) { source.maxId() }
        val fresh = request.sinceId == 0L && request.backfillBeforeId == 0L
        log("sms sync: start fresh=$fresh maxId=$maxId pageSize=$pageSize")
        val cursors =
            if (fresh) {
                Cursors(highWatermark = maxId, backfillCursor = maxId + 1, backfillComplete = maxId == 0L)
            } else {
                Cursors(request.sinceId, request.backfillBeforeId, backfillComplete = request.backfillBeforeId == 0L)
            }
        val pages = PageSender(cursors)
        if (!fresh) sendForward(cursors, pages, pageSize, token)
        if (!cursors.backfillComplete) sendBackfill(cursors, pages, pageSize, token)
        if (!pages.sentAny && !token.superseded) pages.send(emptyList())
    }

    private suspend fun sendForward(
        cursors: Cursors,
        pages: PageSender,
        pageSize: Int,
        token: SyncToken,
    ) {
        while (!token.superseded) {
            val rows = withContext(ioDispatcher) { source.newerThan(cursors.highWatermark, pageSize) }
            if (rows.isEmpty()) return
            cursors.highWatermark = rows.last().id
            pages.send(rows)
        }
    }

    private suspend fun sendBackfill(
        cursors: Cursors,
        pages: PageSender,
        pageSize: Int,
        token: SyncToken,
    ) {
        while (!token.superseded && !cursors.backfillComplete) {
            val rows = withContext(ioDispatcher) { source.olderThan(cursors.backfillCursor, pageSize + 1) }
            val page = rows.take(pageSize)
            cursors.backfillComplete = rows.size <= pageSize
            if (page.isNotEmpty()) cursors.backfillCursor = page.last().id
            pages.send(page)
        }
    }

    private class Cursors(
        var highWatermark: Long,
        var backfillCursor: Long,
        var backfillComplete: Boolean,
    )

    private inner class PageSender(
        private val cursors: Cursors,
    ) {
        private var firstPage = true
        val sentAny get() = !firstPage

        suspend fun send(messages: List<SmsMessage>) {
            val threads = if (firstPage) withContext(ioDispatcher) { source.threads() } else emptyList()
            firstPage = false
            session.send(Channel.CHANNEL_SMS) {
                smsSyncResponse =
                    smsSyncResponse {
                        status = SmsSyncStatus.SMS_SYNC_STATUS_OK
                        this.threads += threads
                        this.messages += messages
                        highWatermarkId = cursors.highWatermark
                        backfillCursorId = cursors.backfillCursor
                        backfillComplete = cursors.backfillComplete
                    }
            }
            log(
                "sms sync: sent page messages=${messages.size} " +
                    "high=${cursors.highWatermark} cursor=${cursors.backfillCursor}",
            )
        }
    }

    /** Set by [run] when a newer request arrives; checked between pages. */
    class SyncToken {
        @Volatile
        var superseded: Boolean = false
    }
}
