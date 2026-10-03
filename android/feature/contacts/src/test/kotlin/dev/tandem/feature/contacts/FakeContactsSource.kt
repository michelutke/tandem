package dev.tandem.feature.contacts

import dev.tandem.protocol.v1.Contact
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

class FakeContactsSource(
    private val contacts: List<Contact> = emptyList(),
    private val pageSize: Int = ContactsSource.PAGE_SIZE,
    private val readPermitted: Boolean = true,
    private val deletedContactIds: List<String> = emptyList(),
) : ContactsSource {
    val changeEvents = MutableSharedFlow<Unit>(extraBufferCapacity = 64)

    var pagesRead = 0
        private set

    override fun hasReadPermission(): Boolean = readPermitted

    override fun readPage(
        afterContactId: Long,
        sinceUpdatedAtMs: Long,
    ): ContactsPage {
        pagesRead++
        val remaining = contacts.filter { it.contactId.toLong() > afterContactId && it.updatedAtMs > sinceUpdatedAtMs }
        val page = remaining.take(pageSize)
        val nextAfterContactId = if (remaining.size > pageSize) page.last().contactId.toLong() else null
        return ContactsPage(page, nextAfterContactId)
    }

    override fun readDeletedContactIds(sinceDeletedAtMs: Long): List<String> = deletedContactIds

    override fun changes(): Flow<Unit> = changeEvents
}
