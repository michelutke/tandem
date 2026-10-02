package dev.tandem.feature.contacts

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.ContactsSyncRequest
import dev.tandem.protocol.v1.ContactsSyncStatus
import dev.tandem.protocol.v1.contactsSyncResponse
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.withContext

/**
 * E51-02 phone side of the CONTACTS channel sync (PRD F-8.3, docs/protocol/SPEC.md
 * #contacts-channel): answers each `ContactsSyncRequest` with `ContactsSyncResponse` pages read
 * from [source] on [ioDispatcher]. Pages are read and sent one at a time; [TandemSession.send]
 * suspends while the CONTACTS channel has no send credit, so no further page is read or sent
 * until credit returns.
 */
class ContactsSyncSession(
    private val source: ContactsSource,
    private val session: TandemSession,
    private val ioDispatcher: CoroutineDispatcher,
) {
    /** Handles every `ContactsSyncRequest` received on the CONTACTS channel, one at a time. */
    suspend fun run() {
        session
            .receive(Channel.CHANNEL_CONTACTS)
            .filter { it.hasContactsSyncRequest() }
            .collect { handle(it.contactsSyncRequest) }
    }

    suspend fun handle(request: ContactsSyncRequest) {
        if (!source.hasReadPermission()) {
            sendPermissionRequired()
            return
        }

        var watermarkMs = request.sinceUpdatedAtMs
        var afterContactId: Long? = 0
        while (afterContactId != null) {
            val page = withContext(ioDispatcher) { source.readPage(afterContactId!!) }
            val changed = page.contacts.filter { it.updatedAtMs > request.sinceUpdatedAtMs }
            watermarkMs = maxOf(watermarkMs, page.contacts.maxOfOrNull { it.updatedAtMs } ?: watermarkMs)
            afterContactId = page.nextAfterContactId
            val isLastPage = afterContactId == null
            if (changed.isEmpty() && !isLastPage) continue

            session.send(Channel.CHANNEL_CONTACTS) {
                contactsSyncResponse =
                    contactsSyncResponse {
                        status = ContactsSyncStatus.CONTACTS_SYNC_STATUS_OK
                        contacts += changed
                        complete = isLastPage
                        if (isLastPage) this.watermarkMs = watermarkMs
                    }
            }
        }
    }

    private suspend fun sendPermissionRequired() {
        session.send(Channel.CHANNEL_CONTACTS) {
            contactsSyncResponse =
                contactsSyncResponse {
                    status = ContactsSyncStatus.CONTACTS_SYNC_STATUS_PERMISSION_REQUIRED
                    complete = true
                }
        }
    }
}
