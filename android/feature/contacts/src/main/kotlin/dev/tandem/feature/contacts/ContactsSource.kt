package dev.tandem.feature.contacts

import dev.tandem.protocol.v1.Contact
import kotlinx.coroutines.flow.Flow

/**
 * One page of contacts ordered by ascending contact id. [nextAfterContactId] is the id to pass to
 * the next [ContactsSource.readPage] call, or `null` when this is the last page.
 */
data class ContactsPage(
    val contacts: List<Contact>,
    val nextAfterContactId: Long?,
)

/**
 * E51-02 feature-local seam over the phone's contacts store: [ContactsSyncSession] reads contacts
 * only through this interface, so tests script it with `FakeContactsSource` instead of a real
 * ContactsContract provider.
 */
interface ContactsSource {
    /** Whether READ_CONTACTS is currently granted. */
    fun hasReadPermission(): Boolean

    /**
     * Up to [PAGE_SIZE] contacts with an id greater than [afterContactId] and `updatedAtMs` greater
     * than [sinceUpdatedAtMs], ordered by id.
     */
    fun readPage(
        afterContactId: Long,
        sinceUpdatedAtMs: Long = 0,
    ): ContactsPage

    /** Ids of contacts deleted after [sinceDeletedAtMs] (E51-05 tombstones). */
    fun readDeletedContactIds(sinceDeletedAtMs: Long): List<String>

    /** Emits once per raw change callback of the contacts store; callers debounce. */
    fun changes(): Flow<Unit>

    companion object {
        const val PAGE_SIZE = 200
    }
}
