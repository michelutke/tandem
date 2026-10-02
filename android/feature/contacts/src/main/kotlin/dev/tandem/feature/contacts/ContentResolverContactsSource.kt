package dev.tandem.feature.contacts

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract.CommonDataKinds.Email
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.Contacts
import android.provider.ContactsContract.DeletedContacts
import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.Contact
import dev.tandem.protocol.v1.ContactAddressType
import dev.tandem.protocol.v1.ContactKt.email
import dev.tandem.protocol.v1.ContactKt.phoneNumber
import dev.tandem.protocol.v1.contact
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.io.IOException

/**
 * [ContactsSource] over `ContactsContract` (PRD F-8.3). Pages `Contacts` by `_ID` window and joins
 * the `Phone`/`Email` data rows for that window; every cursor is closed before the next query.
 * Never logs names, numbers or addresses (invariant 7).
 */
class ContentResolverContactsSource(
    private val context: Context,
    private val thumbnailScaler: ThumbnailScaler = ThumbnailScaler(),
) : ContactsSource {
    private val resolver: ContentResolver get() = context.contentResolver

    override fun hasReadPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    override fun readPage(
        afterContactId: Long,
        sinceUpdatedAtMs: Long,
    ): ContactsPage {
        val rows = readContactRows(afterContactId, sinceUpdatedAtMs)
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

    override fun readDeletedContactIds(sinceDeletedAtMs: Long): List<String> {
        val ids = mutableListOf<String>()
        resolver
            .query(
                DeletedContacts.CONTENT_URI,
                arrayOf(DeletedContacts.CONTACT_ID),
                "${DeletedContacts.CONTACT_DELETED_TIMESTAMP} > ?",
                arrayOf(sinceDeletedAtMs.toString()),
                "${DeletedContacts.CONTACT_ID} ASC",
            )?.use { cursor -> cursor.forEachRow { ids += it.getLong(0).toString() } }
        return ids
    }

    override fun changes(): Flow<Unit> =
        callbackFlow {
            val observer =
                object : ContentObserver(Handler(Looper.getMainLooper())) {
                    override fun onChange(selfChange: Boolean) {
                        trySend(Unit)
                    }
                }
            resolver.registerContentObserver(Contacts.CONTENT_URI, true, observer)
            awaitClose { resolver.unregisterContentObserver(observer) }
        }

    private fun readContactRows(
        afterContactId: Long,
        sinceUpdatedAtMs: Long,
    ): List<ContactRow> {
        val queryArgs =
            Bundle().apply {
                putString(
                    ContentResolver.QUERY_ARG_SQL_SELECTION,
                    "${Contacts._ID} > ? AND ${Contacts.CONTACT_LAST_UPDATED_TIMESTAMP} > ?",
                )
                putStringArray(
                    ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
                    arrayOf(afterContactId.toString(), sinceUpdatedAtMs.toString()),
                )
                putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, "${Contacts._ID} ASC")
                putInt(ContentResolver.QUERY_ARG_LIMIT, ContactsSource.PAGE_SIZE + 1)
            }
        val projection =
            arrayOf(
                Contacts._ID,
                Contacts.DISPLAY_NAME_PRIMARY,
                Contacts.CONTACT_LAST_UPDATED_TIMESTAMP,
                Contacts.PHOTO_THUMBNAIL_URI,
            )
        val rows = mutableListOf<ContactRow>()
        resolver.query(Contacts.CONTENT_URI, projection, queryArgs, null)?.use { cursor ->
            while (rows.size <= ContactsSource.PAGE_SIZE && cursor.moveToNext()) {
                rows +=
                    ContactRow(
                        cursor.getLong(0),
                        cursor.getString(1).orEmpty(),
                        cursor.getLong(2),
                        cursor.getString(PHOTO_URI_COLUMN),
                    )
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
        val photoThumbnailUri: String?,
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
            readThumbnail(photoThumbnailUri)?.let { photoThumbnail = ByteString.copyFrom(it) }
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

    private fun readThumbnail(uri: String?): ByteArray? =
        uri?.let {
            try {
                resolver.openInputStream(Uri.parse(it))?.use { stream -> thumbnailScaler.scale(stream.readBytes()) }
            } catch (_: IOException) {
                null
            }
        }

    private companion object {
        const val PHOTO_URI_COLUMN = 3
        val PHONE_COLUMNS = DataColumns(Phone.CONTENT_URI, Phone.CONTACT_ID, Phone.NUMBER, Phone.TYPE)
        val EMAIL_COLUMNS = DataColumns(Email.CONTENT_URI, Email.CONTACT_ID, Email.ADDRESS, Email.TYPE)
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
