package dev.tandem.feature.messaging

import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.sendOrDrop
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsSyncStatus
import dev.tandem.protocol.v1.SmsThread
import dev.tandem.protocol.v1.smsSyncResponse
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.channels.Channel.Factory.CONFLATED
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * E50-03 live-session SMS push (PRD F-8.1): after each provider change burst, pushes rows newer
 * than the in-memory last-sent id as one unsolicited `SmsSyncResponse`. No watermark is persisted;
 * the Mac's next `SmsSyncRequest` supplies `sinceId`. [log] receives counts and ids only, never
 * message bodies or addresses (invariant 7).
 */
@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
class SmsIncrementalSync(
    private val source: SmsSource,
    private val session: TandemSession,
    private val ioDispatcher: CoroutineDispatcher,
    private val log: (String) -> Unit = {},
) {
    /**
     * Subscribes to [SmsSource.changes] before calling [initialLastSentId] (the Mac's sinceId or
     * the fresh-sync snapshot max), then pushes on every debounced change until cancelled.
     */
    suspend fun run(initialLastSentId: suspend () -> Long) {
        coroutineScope {
            val pending = KtChannel<Unit>(CONFLATED)
            launch(start = CoroutineStart.UNDISPATCHED) {
                source.changes().collect { pending.trySend(Unit) }
            }
            var lastSentId: Long? = baselineOrNull(initialLastSentId)
            pending
                .receiveAsFlow()
                .debounce(DEBOUNCE_MS)
                .collect { lastSentId = pushWhenPermitted(lastSentId, initialLastSentId) }
        }
    }

    // Without READ_SMS the baseline is unknown; the grant happens mid-session, so retry on the next change.
    private suspend fun baselineOrNull(initialLastSentId: suspend () -> Long): Long? =
        try {
            initialLastSentId()
        } catch (_: SmsPermissionMissing) {
            null
        }

    // Without a baseline the change that follows the grant is usually the new message itself, so the
    // snapshot max is not used as the baseline (it would swallow that message); the newest row is pushed.
    private suspend fun pushWhenPermitted(
        lastSentId: Long?,
        initialLastSentId: suspend () -> Long,
    ): Long? =
        try {
            push(lastSentId ?: (initialLastSentId() - 1).coerceAtLeast(0))
        } catch (_: SmsPermissionMissing) {
            lastSentId
        }

    private suspend fun push(lastSentId: Long): Long {
        var cursor = lastSentId
        while (true) {
            val rows =
                withContext(ioDispatcher) { source.newerThan(cursor, SmsSource.PAGE_SIZE) }
                    .takeWithinBytes(PAGE_BYTE_BUDGET) { it.serializedSize }
            if (rows.isEmpty()) return cursor
            val threads = withContext(ioDispatcher) { source.threads() }
            val threadChunks = threads.chunkedByBytes(PAGE_BYTE_BUDGET) { it.serializedSize }
            threadChunks.dropLast(1).forEach { sendResponse(it, emptyList(), cursor) }
            cursor = rows.last().id
            sendResponse(threadChunks.last(), rows, cursor)
            log("sms incremental: pushed messages=${rows.size} high=$cursor")
        }
    }

    private suspend fun sendResponse(
        threads: List<SmsThread>,
        rows: List<SmsMessage>,
        highWatermark: Long,
    ) {
        session.sendOrDrop(Channel.CHANNEL_SMS) {
            smsSyncResponse =
                smsSyncResponse {
                    status = SmsSyncStatus.SMS_SYNC_STATUS_OK
                    this.threads += threads
                    messages += rows
                    highWatermarkId = highWatermark
                }
        }
    }

    companion object {
        const val DEBOUNCE_MS = 250L
    }
}
