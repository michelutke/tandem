package dev.tandem.feature.files

import android.content.ContentResolver
import android.database.Cursor
import android.os.Bundle
import android.provider.MediaStore

/** Real [MediaStoreSource]; the cursor position is bound through selectionArgs only. */
class ContentResolverMediaStoreSource(
    private val contentResolver: ContentResolver,
) : MediaStoreSource {
    override fun query(
        after: MediaKey?,
        limit: Int,
    ): List<MediaRow> {
        val args =
            Bundle().apply {
                putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, SORT_ORDER)
                putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                if (after != null) {
                    putString(ContentResolver.QUERY_ARG_SQL_SELECTION, KEYSET_SELECTION)
                    putStringArray(
                        ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
                        arrayOf(after.dateTaken.toString(), after.dateTaken.toString(), after.id.toString()),
                    )
                }
            }
        val cursor =
            contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, PROJECTION, args, null)
                ?: return emptyList()
        return cursor.use { readRows(it) }
    }

    private fun readRows(cursor: Cursor): List<MediaRow> {
        val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
        val dateColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
        val widthColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
        val heightColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
        return buildList {
            while (cursor.moveToNext()) {
                add(
                    MediaRow(
                        id = cursor.getLong(idColumn),
                        dateTaken = cursor.getLong(dateColumn),
                        width = cursor.getInt(widthColumn),
                        height = cursor.getInt(heightColumn),
                    ),
                )
            }
        }
    }

    private companion object {
        const val SORT_ORDER = "${MediaStore.Images.Media.DATE_TAKEN} DESC, ${MediaStore.Images.Media._ID} DESC"
        const val KEYSET_SELECTION =
            "${MediaStore.Images.Media.DATE_TAKEN} < ? OR " +
                "(${MediaStore.Images.Media.DATE_TAKEN} = ? AND ${MediaStore.Images.Media._ID} < ?)"
        val PROJECTION =
            arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DATE_TAKEN,
                MediaStore.Images.Media.WIDTH,
                MediaStore.Images.Media.HEIGHT,
            )
    }
}
