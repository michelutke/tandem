package dev.tandem.feature.contacts

import dev.tandem.protocol.v1.Contact

class FakeContactsSource(
    private val contacts: List<Contact> = emptyList(),
    private val pageSize: Int = ContactsSource.PAGE_SIZE,
    private val readPermitted: Boolean = true,
) : ContactsSource {
    var pagesRead = 0
        private set

    override fun hasReadPermission(): Boolean = readPermitted

    override fun readPage(afterContactId: Long): ContactsPage {
        pagesRead++
        val remaining = contacts.filter { it.contactId.toLong() > afterContactId }
        val page = remaining.take(pageSize)
        val nextAfterContactId = if (remaining.size > pageSize) page.last().contactId.toLong() else null
        return ContactsPage(page, nextAfterContactId)
    }
}
