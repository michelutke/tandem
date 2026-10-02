package dev.tandem.feature.contacts

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.ContactsContract.CommonDataKinds.Email
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.Contacts
import dev.tandem.protocol.v1.Contact
import dev.tandem.protocol.v1.ContactAddressType
import dev.tandem.protocol.v1.ContactKt.email
import dev.tandem.protocol.v1.ContactKt.phoneNumber
import dev.tandem.protocol.v1.contact

/**
 * [ContactsSource] over `ContactsContract` (PRD F-8.3). Pages `Contacts` by `_ID` window and joins
 * the `Phone`/`Email` data rows for that window; every cursor is closed before the next query.
 * Never logs names, numbers or addresses (invariant 7).
 */
class ContentResolverContactsSource(
    private val context: Context,
) : ContactsSource {
    private val resolver: ContentResolver get() = context.contentResolver

    override fun hasReadPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    override fun readPage(afterContactId: Long): ContactsPage {
        val rows = readContactRows(afterContactId)
        val pageRows = rows.take(ContactsSource.PAGE_SIZE)
        if (pageRows.isEmpty()) return ContactsPage(emptyList(), null)

        val minId = pageRows.first().id
        val maxId = pageRows.last().id
        val phones = readDataRows(PHONE_COLUMNS, minId, maxId)
        val emails = readDataRows(EMAIL_COLUMNS, minId, maxId)

        val contacts = pageRows.map { it.toContact(phones[it.id].orEmpty(), emails[it.id].orEmpty()) }
        val hasMore = rows.size > ContactsSource.PAGE_SIZE
        return ContactsPage(contacts, if (hasMore) maxId else null)
    }

    private fun readContactRows(afterContactId: Long): List<ContactRow> {
        val queryArgs =
            Bundle().apply {
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, "${Contacts._ID} > ?")
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, arrayOf(afterContactId.toString()))
                putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, "${Contacts._ID} ASC")
                putInt(ContentResolver.QUERY_ARG_LIMIT, ContactsSource.PAGE_SIZE + 1)
            }
        val projection = arrayOf(Contacts._ID, Contacts.DISPLAY_NAME_PRIMARY, Contacts.CONTACT_LAST_UPDATED_TIMESTAMP)
        val rows = mutableListOf<ContactRow>()
        resolver.query(Contacts.CONTENT_URI, projection, queryArgs, null)?.use { cursor ->
            while (rows.size <= ContactsSource.PAGE_SIZE && cursor.moveToNext()) {
                rows += ContactRow(cursor.getLong(0), cursor.getString(1).orEmpty(), cursor.getLong(2))
            }
        }
        return rows
    }

    private fun readDataRows(
        columns: DataColumns,
        minId: Long,
        maxId: Long,
    ): Map<Long, List<DataRow>> {
        val rows = mutableListOf<Pair<Long, DataRow>>()
        resolver
            .query(
                columns.uri,
                arrayOf(columns.contactId, columns.value, columns.type),
                "${columns.contactId} BETWEEN ? AND ?",
                arrayOf(minId.toString(), maxId.toString()),
                null,
            )?.use { cursor ->
                cursor.forEachRow {
                    rows += it.getLong(0) to DataRow(it.getString(1).orEmpty(), it.getInt(2))
                }
            }
        return rows.groupBy({ it.first }, { it.second })
    }

    private inline fun Cursor.forEachRow(block: (Cursor) -> Unit) {
        while (moveToNext()) block(this)
    }

    private class DataColumns(
        val uri: Uri,
        val contactId: String,
        val value: String,
        val type: String,
    )

    private class ContactRow(
        val id: Long,
        val displayName: String,
        val updatedAtMs: Long,
    )

    private class DataRow(
        val value: String,
        val type: Int,
    )

    private fun ContactRow.toContact(
        phones: List<DataRow>,
        emails: List<DataRow>,
    ): Contact =
        contact {
            contactId = id.toString()
            displayName = this@toContact.displayName
            updatedAtMs = this@toContact.updatedAtMs
            phoneNumbers +=
                phones.map { row ->
                    phoneNumber {
                        number = row.value
                        type = phoneType(row.type)
                    }
                }
            this.emails +=
                emails.map { row ->
                    email {
                        address = row.value
                        type = emailType(row.type)
                    }
                }
        }

    private fun phoneType(type: Int): ContactAddressType =
        when (type) {
            Phone.TYPE_HOME -> ContactAddressType.CONTACT_ADDRESS_TYPE_HOME
            Phone.TYPE_WORK -> ContactAddressType.CONTACT_ADDRESS_TYPE_WORK
            Phone.TYPE_MOBILE -> ContactAddressType.CONTACT_ADDRESS_TYPE_MOBILE
            else -> ContactAddressType.CONTACT_ADDRESS_TYPE_OTHER
        }

    private fun emailType(type: Int): ContactAddressType =
        when (type) {
            Email.TYPE_HOME -> ContactAddressType.CONTACT_ADDRESS_TYPE_HOME
            Email.TYPE_WORK -> ContactAddressType.CONTACT_ADDRESS_TYPE_WORK
            Email.TYPE_MOBILE -> ContactAddressType.CONTACT_ADDRESS_TYPE_MOBILE
            else -> ContactAddressType.CONTACT_ADDRESS_TYPE_OTHER
        }

    private companion object {
        val PHONE_COLUMNS = DataColumns(Phone.CONTENT_URI, Phone.CONTACT_ID, Phone.NUMBER, Phone.TYPE)
        val EMAIL_COLUMNS = DataColumns(Email.CONTENT_URI, Email.CONTACT_ID, Email.ADDRESS, Email.TYPE)
    }
}
