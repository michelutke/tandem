package dev.tandem.feature.messaging

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
import android.provider.Telephony
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsThread
import dev.tandem.protocol.v1.copy
import dev.tandem.protocol.v1.smsThread
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

private fun Cursor.long(column: String): Long = getLong(getColumnIndexOrThrow(column))

private fun Cursor.int(column: String): Int = getInt(getColumnIndexOrThrow(column))

private fun Cursor.string(column: String): String = getString(getColumnIndexOrThrow(column)).orEmpty()

/**
 * [SmsSource] over `content://sms` and `content://mms-sms/conversations` (PRD F-8.1). Text-only:
 * MMS rows live outside `content://sms` and are never queried. Every query is limit-bounded and
 * its cursor closed before returning. Never logs addresses or bodies (invariant 7).
 */
class ContentResolverSmsSource(
    private val context: Context,
) : SmsSource {
    private val resolver: ContentResolver get() = context.contentResolver

    override fun threads(): List<SmsThread> {
        val threads = readThreads()
        val unreadCounts = unreadCountsByThread(threads.map { it.threadId })
        return threads.map { it.copy { unreadCount = unreadCounts[it.threadId] ?: 0 } }
    }

    private fun readThreads(): List<SmsThread> =
        query(
            SmsQuery(
                uri = Telephony.MmsSms.CONTENT_CONVERSATIONS_URI,
                projection = THREAD_PROJECTION,
                sortOrder = "${Telephony.Sms.DATE} DESC",
                limit = SmsSource.PAGE_SIZE,
            ),
        ) {
            smsThread {
                threadId = it.long(Telephony.Sms.THREAD_ID)
                address = it.string(Telephony.Sms.ADDRESS)
                snippet = it.string(Telephony.Sms.BODY)
                lastMessageAtMs = it.long(Telephony.Sms.DATE)
            }
        }

    override fun newerThan(
        sinceId: Long,
        limit: Int,
    ): List<SmsMessage> = readMessages("${Telephony.Sms._ID} > ?", sinceId, "ASC", limit)

    override fun olderThan(
        beforeId: Long,
        limit: Int,
    ): List<SmsMessage> = readMessages("${Telephony.Sms._ID} < ?", beforeId, "DESC", limit)

    override fun maxId(): Long =
        query(
            SmsQuery(
                uri = Telephony.Sms.CONTENT_URI,
                projection = arrayOf(Telephony.Sms._ID),
                sortOrder = "${Telephony.Sms._ID} DESC",
                limit = 1,
            ),
        ) { it.long(Telephony.Sms._ID) }.firstOrNull() ?: 0L

    override fun changes(): Flow<Unit> =
        callbackFlow {
            val observer =
                object : ContentObserver(Handler(Looper.getMainLooper())) {
                    override fun onChange(selfChange: Boolean) {
                        trySend(Unit)
                    }
                }
            resolver.registerContentObserver(Telephony.Sms.CONTENT_URI, true, observer)
            awaitClose { resolver.unregisterContentObserver(observer) }
        }

    private fun unreadCountsByThread(threadIds: List<Long>): Map<Long, Int> {
        if (threadIds.isEmpty()) return emptyMap()
        val placeholders = threadIds.joinToString(",") { "?" }
        return query(
            SmsQuery(
                uri = Telephony.Sms.CONTENT_URI,
                projection = arrayOf(Telephony.Sms.THREAD_ID),
                selection = "${Telephony.Sms.READ} = 0 AND ${Telephony.Sms.THREAD_ID} IN ($placeholders)",
                selectionArgs = threadIds.map { it.toString() }.toTypedArray(),
                sortOrder = "${Telephony.Sms._ID} ASC",
                limit = Int.MAX_VALUE,
            ),
        ) { it.long(Telephony.Sms.THREAD_ID) }.groupingBy { it }.eachCount()
    }

    private fun readMessages(
        selection: String,
        idBound: Long,
        direction: String,
        limit: Int,
    ): List<SmsMessage> =
        query(
            SmsQuery(
                uri = Telephony.Sms.CONTENT_URI,
                projection = MESSAGE_PROJECTION,
                selection = selection,
                selectionArgs = arrayOf(idBound.toString()),
                sortOrder = "${Telephony.Sms._ID} $direction",
                limit = limit,
            ),
        ) {
            SmsRowMapper.toMessage(
                SmsRow(
                    id = it.long(Telephony.Sms._ID),
                    threadId = it.long(Telephony.Sms.THREAD_ID),
                    address = it.string(Telephony.Sms.ADDRESS),
                    body = it.string(Telephony.Sms.BODY),
                    dateMs = it.long(Telephony.Sms.DATE),
                    providerType = it.int(Telephony.Sms.TYPE),
                    subscriptionId = it.int(Telephony.Sms.SUBSCRIPTION_ID),
                ),
            )
        }

    private fun <T> query(
        spec: SmsQuery,
        mapRow: (Cursor) -> T,
    ): List<T> {
        if (context.checkSelfPermission(Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
            throw SmsPermissionMissing()
        }
        val queryArgs =
            Bundle().apply {
                spec.selection?.let { putString(ContentResolver.QUERY_ARG_SQL_SELECTION, it) }
                spec.selectionArgs?.let { putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, it) }
                putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, spec.sortOrder)
                putInt(ContentResolver.QUERY_ARG_LIMIT, spec.limit)
            }
        val rows = mutableListOf<T>()
        try {
            resolver.query(spec.uri, spec.projection, queryArgs, null)?.use { cursor ->
                while (rows.size < spec.limit && cursor.moveToNext()) rows += mapRow(cursor)
            }
        } catch (_: SecurityException) {
            throw SmsPermissionMissing()
        }
        return rows
    }

    private class SmsQuery(
        val uri: Uri,
        val projection: Array<String>,
        val sortOrder: String,
        val limit: Int,
        val selection: String? = null,
        val selectionArgs: Array<String>? = null,
    )

    private companion object {
        val MESSAGE_PROJECTION =
            arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.THREAD_ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.TYPE,
                Telephony.Sms.SUBSCRIPTION_ID,
            )
        val THREAD_PROJECTION =
            arrayOf(Telephony.Sms.THREAD_ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE)
    }
}
