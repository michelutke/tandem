package dev.tandem.feature.messaging

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.SmsSyncStatus
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
            var lastSentId = initialLastSentId()
            pending
                .receiveAsFlow()
                .debounce(DEBOUNCE_MS)
                .collect { lastSentId = push(lastSentId) }
        }
    }

    private suspend fun push(lastSentId: Long): Long {
        var cursor = lastSentId
        while (true) {
            val rows = withContext(ioDispatcher) { source.newerThan(cursor, SmsSource.PAGE_SIZE) }
            if (rows.isEmpty()) return cursor
            cursor = rows.last().id
            val threads = withContext(ioDispatcher) { source.threads() }
            session.send(Channel.CHANNEL_SMS) {
                smsSyncResponse =
                    smsSyncResponse {
                        status = SmsSyncStatus.SMS_SYNC_STATUS_OK
                        this.threads += threads
                        messages += rows
                        highWatermarkId = cursor
                    }
            }
            log("sms incremental: pushed messages=${rows.size} high=$cursor")
        }
    }

    companion object {
        const val DEBOUNCE_MS = 250L
    }
}
