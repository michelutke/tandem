package dev.tandem.feature.files

import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.PhotoErrorReason
import dev.tandem.protocol.v1.PhotoPageResult
import dev.tandem.protocol.v1.photoPage
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PhotoPagerTest {
    private class FakeMediaStoreSource(
        rows: List<MediaRow>,
    ) : MediaStoreSource {
        private val rows = rows.toMutableList()
        var rowsRead = 0
        var requestedLimits = mutableListOf<Int>()

        fun insert(row: MediaRow) {
            rows += row
        }

        override fun query(
            after: MediaKey?,
            limit: Int,
        ): List<MediaRow> {
            requestedLimits += limit
            val ordered = rows.sortedWith(compareByDescending<MediaRow> { it.dateTaken }.thenByDescending { it.id })
            val matching =
                if (after == null) {
                    ordered
                } else {
                    ordered.filter {
                        it.dateTaken < after.dateTaken || (it.dateTaken == after.dateTaken && it.id < after.id)
                    }
                }
            return matching.take(limit).also { rowsRead += it.size }
        }
    }

    private fun row(
        id: Long,
        dateTaken: Long = id * 1000,
    ) = MediaRow(id = id, dateTaken = dateTaken, width = 4000, height = 3000)

    private fun PhotoPager.fetch(
        cursor: String = "",
        limit: Int = 100,
    ): PhotoPageResult {
        val outcome =
            page(
                photoPage {
                    this.cursor = cursor
                    this.limit = limit
                },
                PhotoAccess.PHOTO_ACCESS_FULL,
            )
        return (outcome as PhotoPageOutcome.Page).result
    }

    private fun PhotoPager.fetchAll(limit: Int): List<PhotoPageResult> {
        val pages = mutableListOf<PhotoPageResult>()
        var cursor = ""
        do {
            val result = fetch(cursor, limit)
            pages += result
            cursor = result.nextCursor
        } while (cursor.isNotEmpty())
        return pages
    }

    @Test
    fun photoPaging_items250Limit100_pagesOf100And100And50ThenNoCursor() {
        val source = FakeMediaStoreSource((1L..250L).map { row(it) })

        val pages = PhotoPager(source).fetchAll(limit = 100)

        assertEquals(listOf(100, 100, 50), pages.map { it.itemsCount })
        assertTrue(pages.last().nextCursor.isEmpty())
        assertEquals(
            250,
            pages
                .flatMap { it.itemsList }
                .map { it.id }
                .toSet()
                .size,
        )
        assertTrue(source.rowsRead <= 250 + 3, "rowsRead=${source.rowsRead}")
    }

    @Test
    fun photoPaging_sameDateTakenAcrossBoundary_noDuplicatesOrGaps() {
        val source = FakeMediaStoreSource((1L..25L).map { row(it, dateTaken = 5000) })

        val ids = PhotoPager(source).fetchAll(limit = 10).flatMap { it.itemsList }.map { it.id }

        assertEquals((25L downTo 1L).map { it.toString() }, ids)
    }

    @Test
    fun photoPaging_newerPhotoInsertedBetweenPages_laterPagesUnchanged() {
        val source = FakeMediaStoreSource((1L..30L).map { row(it) })
        val pager = PhotoPager(source)
        val first = pager.fetch(limit = 10)
        val expectedSecond = pager.fetch(first.nextCursor, 10)

        source.insert(row(999))

        assertEquals(expectedSecond, pager.fetch(first.nextCursor, 10))
    }

    @Test
    fun photoPaging_limit500_clampedTo200() {
        val source = FakeMediaStoreSource((1L..250L).map { row(it) })

        val result = PhotoPager(source).fetch(limit = 500)

        assertEquals(200, result.itemsCount)
    }

    @Test
    fun photoPaging_limitUnset_servedAs100() {
        val source = FakeMediaStoreSource((1L..250L).map { row(it) })

        assertEquals(100, PhotoPager(source).fetch(limit = 0).itemsCount)
    }

    @Test
    fun photoPaging_sqlFragmentCursor_invalidCursorErrorNoItems() {
        val source = FakeMediaStoreSource((1L..10L).map { row(it) })

        val outcome =
            PhotoPager(source).page(
                photoPage {
                    cursor = "') OR 1=1 --"
                    limit = 10
                },
                PhotoAccess.PHOTO_ACCESS_FULL,
            )

        val failure = outcome as PhotoPageOutcome.Failure
        assertEquals(PhotoErrorReason.PHOTO_ERROR_REASON_INVALID_CURSOR, failure.error.reason)
        assertEquals(0, source.rowsRead)
    }

    @Test
    fun photoPaging_nonCanonicalCursors_invalidCursor() {
        val pager = PhotoPager(FakeMediaStoreSource(listOf(row(1))))

        listOf("1", "1:2:3", "a:b", "+1:2", "01:2", "1: 2", "99999999999999999999:1").forEach { cursor ->
            val outcome = pager.page(photoPage { this.cursor = cursor }, PhotoAccess.PHOTO_ACCESS_FULL)
            assertTrue(outcome is PhotoPageOutcome.Failure, cursor)
        }
    }
}
