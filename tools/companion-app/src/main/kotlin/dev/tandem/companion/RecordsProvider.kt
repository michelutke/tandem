package dev.tandem.companion

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri

/**
 * E00-22: debug-only read-back for [CompanionRecords]. Read-only; the companion app itself never
 * ships (the release scan at tools/release-audit proves `dev.tandem.companion` is absent from
 * android/app's release build).
 */
class RecordsProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? =
        when (MATCHER.match(uri)) {
            ACTIONS -> {
                MatrixCursor(arrayOf(CompanionContract.COLUMN_KEY, CompanionContract.COLUMN_ACTION_ID)).apply {
                    CompanionRecords.actionsFired.forEach { addRow(arrayOf(it.key, it.actionId)) }
                }
            }

            REPLIES -> {
                MatrixCursor(arrayOf(CompanionContract.COLUMN_KEY, CompanionContract.COLUMN_TEXT)).apply {
                    CompanionRecords.repliesReceived.forEach { addRow(arrayOf(it.key, it.text)) }
                }
            }

            else -> {
                null
            }
        }

    override fun getType(uri: Uri): String? = null

    override fun insert(
        uri: Uri,
        values: ContentValues?,
    ): Uri? = null

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private companion object {
        const val ACTIONS = 1
        const val REPLIES = 2
        val MATCHER =
            UriMatcher(UriMatcher.NO_MATCH).apply {
                addURI(CompanionContract.AUTHORITY, CompanionContract.PATH_ACTIONS, ACTIONS)
                addURI(CompanionContract.AUTHORITY, CompanionContract.PATH_REPLIES, REPLIES)
            }
    }
}
