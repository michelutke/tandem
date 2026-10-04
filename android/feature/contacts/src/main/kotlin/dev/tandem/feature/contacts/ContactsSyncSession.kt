package dev.tandem.feature.contacts

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.ContactsSyncRequest
import dev.tandem.protocol.v1.ContactsSyncStatus
import dev.tandem.protocol.v1.contactsSyncRequest
import dev.tandem.protocol.v1.contactsSyncResponse
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.Clock

/**
 * E51-02 phone side of the CONTACTS channel sync (PRD F-8.3, docs/protocol/SPEC.md
 * #contacts-channel): answers each `ContactsSyncRequest` with `ContactsSyncResponse` pages read
 * from [source] on [ioDispatcher]. Pages are read and sent one at a time; [TandemSession.send]
 * suspends while the CONTACTS channel has no send credit, so no further page is read or sent
 * until credit returns. E51-05: only contacts updated after `sinceUpdatedAtMs` plus tombstones are
 * sent, a `since` older than [RETENTION_MS] gets `FULL_RESYNC_REQUIRED`, and [observeChanges]
 * re-syncs from the last completed watermark after a debounced change burst.
 */
class ContactsSyncSession(
    private val source: ContactsSource,
    private val session: TandemSession,
    private val ioDispatcher: CoroutineDispatcher,
    private val clock: Clock,
) {
    private val syncLock = Mutex()
    private var lastWatermarkMs: Long? = null

    /** Handles every `ContactsSyncRequest` received on the CONTACTS channel, one at a time. */
    suspend fun run() {
        session
            .receive(Channel.CHANNEL_CONTACTS)
            .filter { it.hasContactsSyncRequest() }
            .collect { handle(it.contactsSyncRequest) }
    }

    /** Pushes incremental updates once the contacts store has been quiet for [CHANGE_DEBOUNCE_MS]. */
    @OptIn(FlowPreview::class)
    suspend fun observeChanges() {
        source
            .changes()
            .debounce(CHANGE_DEBOUNCE_MS)
            .collect {
                val since = lastWatermarkMs ?: return@collect
                handle(contactsSyncRequest { sinceUpdatedAtMs = since })
            }
    }

    suspend fun handle(request: ContactsSyncRequest) = syncLock.withLock { sync(request) }

    private suspend fun sync(request: ContactsSyncRequest) {
        if (!source.hasReadPermission()) {
            sendPermissionRequired()
            return
        }
        if (isBeyondTombstoneRetention(request.sinceUpdatedAtMs)) {
            sendStatus(ContactsSyncStatus.CONTACTS_SYNC_STATUS_FULL_RESYNC_REQUIRED)
            return
        }

        var watermarkMs = request.sinceUpdatedAtMs
        var afterContactId: Long? = 0
        while (afterContactId != null) {
            val page =
                withContext(ioDispatcher) { source.readPage(afterContactId!!, request.sinceUpdatedAtMs) }
            val changed = page.contacts
            watermarkMs = maxOf(watermarkMs, page.contacts.maxOfOrNull { it.updatedAtMs } ?: watermarkMs)
            afterContactId = page.nextAfterContactId
            val isLastPage = afterContactId == null
            if (changed.isEmpty() && !isLastPage) continue
            val tombstoneIds =
                if (isLastPage && request.sinceUpdatedAtMs > 0) {
                    withContext(ioDispatcher) { source.readDeletedContactIds(request.sinceUpdatedAtMs) }
                } else {
                    emptyList()
                }

            session.send(Channel.CHANNEL_CONTACTS) {
                contactsSyncResponse =
                    contactsSyncResponse {
                        status = ContactsSyncStatus.CONTACTS_SYNC_STATUS_OK
                        contacts += changed
                        deletedContactIds += tombstoneIds
                        complete = isLastPage
                        if (isLastPage) this.watermarkMs = watermarkMs
                    }
            }
        }
        lastWatermarkMs = watermarkMs
    }

    private fun isBeyondTombstoneRetention(sinceUpdatedAtMs: Long): Boolean =
        sinceUpdatedAtMs > 0 && clock.millis() - sinceUpdatedAtMs > RETENTION_MS

    private suspend fun sendPermissionRequired() =
        sendStatus(ContactsSyncStatus.CONTACTS_SYNC_STATUS_PERMISSION_REQUIRED)

    private suspend fun sendStatus(responseStatus: ContactsSyncStatus) {
        session.send(Channel.CHANNEL_CONTACTS) {
            contactsSyncResponse =
                contactsSyncResponse {
                    status = responseStatus
                    complete = true
                }
        }
    }

    private companion object {
        /** `ContactsContract.DeletedContacts.DAYS_KEPT_MILLISECONDS`: 30 days. */
        const val RETENTION_MS = 30L * 24 * 60 * 60 * 1000
        const val CHANGE_DEBOUNCE_MS = 1_000L
    }
}
