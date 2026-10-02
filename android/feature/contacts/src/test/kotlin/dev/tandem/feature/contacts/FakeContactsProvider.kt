package dev.tandem.feature.contacts

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.ContactsContract.CommonDataKinds.Email
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.Contacts

data class FakeContactRow(
    val id: Long,
    val name: String,
    val updatedAtMs: Long,
    val phones: List<Pair<String, Int>> = emptyList(),
    val emails: List<Pair<String, Int>> = emptyList(),
)

class FakeContactsProvider : ContentProvider() {
    var rows: List<FakeContactRow> = emptyList()
    val queriedUris = mutableListOf<Uri>()
    var cursorOpenedWhilePreviousOpen = false
        private set

    private val issuedCursors = mutableListOf<Cursor>()

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor {
        if (issuedCursors.any { !it.isClosed }) cursorOpenedWhilePreviousOpen = true
        queriedUris += uri
        val args = selectionArgs.orEmpty().map { it.toLong() }
        val cursor =
            when (uri) {
                Contacts.CONTENT_URI -> contactsCursor(afterId = args[0])
                Phone.CONTENT_URI -> dataCursor(args[0], args[1]) { it.phones }
                Email.CONTENT_URI -> dataCursor(args[0], args[1]) { it.emails }
                else -> error("unexpected uri $uri")
            }
        issuedCursors += cursor
        return cursor
    }

    private fun contactsCursor(afterId: Long): Cursor {
        val cursor =
            MatrixCursor(
                arrayOf(Contacts._ID, Contacts.DISPLAY_NAME_PRIMARY, Contacts.CONTACT_LAST_UPDATED_TIMESTAMP),
            )
        val matching = rows.filter { it.id > afterId }.sortedBy { it.id }
        matching.forEach { cursor.addRow(arrayOf<Any>(it.id, it.name, it.updatedAtMs)) }
        return cursor
    }

    private fun dataCursor(
        minId: Long,
        maxId: Long,
        values: (FakeContactRow) -> List<Pair<String, Int>>,
    ): Cursor {
        val cursor = MatrixCursor(arrayOf(Phone.CONTACT_ID, Phone.NUMBER, Phone.TYPE))
        rows.filter { it.id in minId..maxId }.forEach { row ->
            values(row).forEach { (value, type) -> cursor.addRow(arrayOf<Any>(row.id, value, type)) }
        }
        return cursor
    }

    override fun getType(uri: Uri): String? = null

    override fun insert(
        uri: Uri,
        values: ContentValues?,
    ): Uri? = null

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<String>?,
    ): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<String>?,
    ): Int = 0
}
