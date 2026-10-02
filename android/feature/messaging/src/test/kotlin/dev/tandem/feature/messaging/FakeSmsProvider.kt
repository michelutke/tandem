package dev.tandem.feature.messaging

import android.content.ContentProvider
import android.content.ContentResolver
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.provider.Telephony

data class FakeSmsRow(
    val id: Long,
    val threadId: Long = 1,
    val address: String = "5551234",
    val body: String = "body $id",
    val dateMs: Long = id,
    val type: Int = Telephony.Sms.MESSAGE_TYPE_INBOX,
    val subId: Int = 1,
    val read: Boolean = true,
) {
    fun value(column: String): Any =
        when (column) {
            Telephony.Sms._ID -> id
            Telephony.Sms.THREAD_ID -> threadId
            Telephony.Sms.ADDRESS -> address
            Telephony.Sms.BODY -> body
            Telephony.Sms.DATE -> dateMs
            Telephony.Sms.TYPE -> type
            Telephony.Sms.SUBSCRIPTION_ID -> subId
            Telephony.Sms.READ -> if (read) 1 else 0
            else -> error("unexpected column $column")
        }
}

data class FakeConversationRow(
    val threadId: Long,
    val address: String,
    val snippet: String,
    val dateMs: Long,
)

/**
 * Fake provider registered for both the `sms` and `mms-sms` authorities. Honours the paging query
 * args (selection id comparison, sort direction, limit) so tests see real windowing.
 */
class FakeSmsProvider : ContentProvider() {
    var smsRows: List<FakeSmsRow> = emptyList()
    var mmsRows: List<FakeSmsRow> = emptyList()
    var conversations: List<FakeConversationRow> = emptyList()
    var failWithSecurityException = false
    val returnedRowCounts = mutableListOf<Int>()
    var cursorOpenedWhilePreviousOpen = false
        private set

    private val issuedCursors = mutableListOf<Cursor>()

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        queryArgs: Bundle?,
        cancellationSignal: CancellationSignal?,
    ): Cursor {
        if (issuedCursors.any { !it.isClosed }) cursorOpenedWhilePreviousOpen = true
        if (failWithSecurityException) throw SecurityException()
        val args = queryArgs ?: Bundle.EMPTY
        val cursor =
            when (uri) {
                Telephony.Sms.CONTENT_URI -> smsCursor(projection.orEmpty().toList().toTypedArray(), args)
                Telephony.MmsSms.CONTENT_CONVERSATIONS_URI -> conversationsCursor(args)
                else -> error("unexpected uri $uri")
            }
        returnedRowCounts += cursor.count
        issuedCursors += cursor
        return cursor
    }

    private fun smsCursor(
        projection: Array<String>,
        args: Bundle,
    ): Cursor {
        val selection = args.getString(ContentResolver.QUERY_ARG_SQL_SELECTION).orEmpty()
        if (selection.startsWith(Telephony.Sms.READ)) return unreadCursor(projection, args)
        val bound = args.getStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS)?.firstOrNull()?.toLong()
        val descending = args.getString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER).orEmpty().contains("DESC")
        val limit = args.getInt(ContentResolver.QUERY_ARG_LIMIT, Int.MAX_VALUE)
        val matching =
            smsRows
                .filter {
                    when {
                        bound == null -> true
                        selection.contains(">") -> it.id > bound
                        else -> it.id < bound
                    }
                }.sortedBy { if (descending) -it.id else it.id }
                .take(limit)
        val cursor = MatrixCursor(projection)
        matching.forEach { row ->
            cursor.addRow(
                projection
                    .map<String, Any> { row.value(it) }
                    .toTypedArray(),
            )
        }
        return cursor
    }

    private fun unreadCursor(
        projection: Array<String>,
        args: Bundle,
    ): Cursor {
        val threadIds = args.getStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS).orEmpty().map { it.toLong() }
        val cursor = MatrixCursor(projection)
        smsRows
            .filter { !it.read && it.threadId in threadIds }
            .forEach { cursor.addRow(arrayOf<Any>(it.threadId)) }
        return cursor
    }

    private fun conversationsCursor(args: Bundle): Cursor {
        val limit = args.getInt(ContentResolver.QUERY_ARG_LIMIT, Int.MAX_VALUE)
        val cursor =
            MatrixCursor(
                arrayOf(Telephony.Sms.THREAD_ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            )
        conversations
            .sortedByDescending { it.dateMs }
            .take(limit)
            .forEach { cursor.addRow(arrayOf<Any>(it.threadId, it.address, it.snippet, it.dateMs)) }
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

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor = error("paged query args expected")
}
