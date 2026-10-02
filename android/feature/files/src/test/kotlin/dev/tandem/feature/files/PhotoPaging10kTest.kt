package dev.tandem.feature.files

import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.PhotoPageResult
import dev.tandem.protocol.v1.photoPage
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.lang.reflect.Modifier

class PhotoPaging10kTest {
    private class CountingSource(
        count: Int,
    ) : MediaStoreSource {
        private val ordered =
            (1L..count).map { MediaRow(id = it, dateTaken = it * 1000, width = 10, height = 10) }.reversed()
        val rowsReadPerQuery = mutableListOf<Int>()

        override fun query(
            after: MediaKey?,
            limit: Int,
        ): List<MediaRow> {
            val matching =
                if (after == null) {
                    ordered
                } else {
                    ordered.dropWhile { it.dateTaken > after.dateTaken || it.id >= after.id }
                }
            return matching.take(limit).also { rowsReadPerQuery += it.size }
        }
    }

    private fun pageThrough(
        source: MediaStoreSource,
        pager: PhotoPager = PhotoPager(source),
    ): List<PhotoPageResult> {
        val pages = mutableListOf<PhotoPageResult>()
        var cursor = ""
        do {
            val outcome =
                pager.page(
                    photoPage {
                        this.cursor = cursor
                        limit = PAGE_LIMIT
                    },
                    PhotoAccess.PHOTO_ACCESS_FULL,
                )
            val result = (outcome as PhotoPageOutcome.Page).result
            pages += result
            cursor = result.nextCursor
        } while (cursor.isNotEmpty())
        return pages
    }

    @Test
    fun photoPaging10k_fullLibrary_exactly10000UniqueIdsIn100Pages() {
        val pages = pageThrough(CountingSource(LIBRARY_SIZE))

        assertEquals(LIBRARY_SIZE / PAGE_LIMIT, pages.size)
        assertEquals(
            LIBRARY_SIZE,
            pages
                .flatMap { it.itemsList }
                .map { it.id }
                .toSet()
                .size,
        )
        assertTrue(pages.last().nextCursor.isEmpty())
    }

    @Test
    fun photoPaging10k_eachPage_readsAtMostLimitPlusOneRows() {
        val source = CountingSource(LIBRARY_SIZE)

        pageThrough(source)

        assertTrue(source.rowsReadPerQuery.all { it <= PAGE_LIMIT + 1 })
    }

    @Test
    fun photoPaging10k_afterResponse_noRowsRetained() {
        val source = CountingSource(LIBRARY_SIZE)
        val pager = PhotoPager(source)

        pageThrough(source, pager)

        assertEquals(
            listOf(MediaStoreSource::class.java),
            pager.javaClass.declaredFields
                .filterNot {
                    Modifier.isStatic(it.modifiers)
                }.map { it.type },
        )
    }

    private companion object {
        const val LIBRARY_SIZE = 10_000
        const val PAGE_LIMIT = 100
    }
}
