package dev.tandem.feature.files

import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.PhotoError
import dev.tandem.protocol.v1.PhotoErrorKind
import dev.tandem.protocol.v1.PhotoErrorReason
import dev.tandem.protocol.v1.PhotoPage
import dev.tandem.protocol.v1.PhotoPageResult
import dev.tandem.protocol.v1.photoError
import dev.tandem.protocol.v1.photoMeta
import dev.tandem.protocol.v1.photoPageResult

sealed interface PhotoPageOutcome {
    data class Page(
        val result: PhotoPageResult,
    ) : PhotoPageOutcome

    data class Failure(
        val error: PhotoError,
    ) : PhotoPageOutcome
}

/**
 * Serves `PhotoPage` from a [MediaStoreSource] with keyset paging. The cursor is untrusted input from
 * the Mac: it must decode to exactly `<dateTaken>:<id>` (two longs) or the page fails with INVALID_CURSOR.
 */
class PhotoPager(
    private val source: MediaStoreSource,
) {
    fun page(
        request: PhotoPage,
        access: PhotoAccess,
    ): PhotoPageOutcome {
        val after =
            if (request.cursor.isEmpty()) {
                null
            } else {
                decodeCursor(request.cursor) ?: return PhotoPageOutcome.Failure(invalidCursor(request.cursor))
            }
        val limit = clampLimit(request.limit)
        val rows = source.query(after, limit + 1)
        val pageRows = rows.take(limit)
        val result =
            photoPageResult {
                this.access = access
                pageRows.forEach { row ->
                    items +=
                        photoMeta {
                            id = row.id.toString()
                            takenAt = row.dateTaken
                            width = row.width
                            height = row.height
                        }
                }
                if (rows.size > limit) nextCursor = encodeCursor(pageRows.last())
            }
        return PhotoPageOutcome.Page(result)
    }

    private fun invalidCursor(cursor: String): PhotoError =
        photoError {
            kind = PhotoErrorKind.PHOTO_ERROR_KIND_PAGE
            ref = cursor.take(MAX_REF_LENGTH)
            reason = PhotoErrorReason.PHOTO_ERROR_REASON_INVALID_CURSOR
        }

    private fun clampLimit(limit: Int): Int =
        when {
            limit == 0 -> DEFAULT_LIMIT
            limit < 0 || limit > MAX_LIMIT -> MAX_LIMIT
            else -> limit
        }

    private fun encodeCursor(row: MediaRow): String = "${row.dateTaken}$CURSOR_SEPARATOR${row.id}"

    private fun decodeCursor(cursor: String): MediaKey? {
        val parts = cursor.split(CURSOR_SEPARATOR)
        val dateTaken = parts.getOrNull(0)?.toLongOrNull()
        val id = parts.getOrNull(1)?.toLongOrNull()
        val isCanonical =
            parts.size == 2 && dateTaken != null && id != null && "$dateTaken$CURSOR_SEPARATOR$id" == cursor
        return if (isCanonical) MediaKey(dateTaken!!, id!!) else null
    }

    private companion object {
        const val DEFAULT_LIMIT = 100
        const val MAX_LIMIT = 200
        const val MAX_REF_LENGTH = 64
        const val CURSOR_SEPARATOR = ":"
    }
}
