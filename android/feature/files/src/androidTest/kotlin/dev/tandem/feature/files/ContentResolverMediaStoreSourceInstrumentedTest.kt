package dev.tandem.feature.files

import android.content.ContentValues
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.photoPage
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

// E41-03 tdd: instrumented: mediaStoreSource_seeded250Images_pagesReturn250UniqueIds
// Runs on the api35 managed device (E00-21) with media access granted by the test harness.
@RunWith(AndroidJUnit4::class)
class ContentResolverMediaStoreSourceInstrumentedTest {
    private val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
    private val seededIds = mutableListOf<Long>()

    @Before
    fun seedImages() {
        repeat(SEED_COUNT) { index ->
            val values =
                ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, "tandem-e41-03-$index.jpg")
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(MediaStore.Images.Media.DATE_TAKEN, SEED_DATE_TAKEN + index / 5)
                    put(MediaStore.Images.Media.WIDTH, 64)
                    put(MediaStore.Images.Media.HEIGHT, 48)
                }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            seededIds += requireNotNull(uri).lastPathSegment!!.toLong()
        }
    }

    @After
    fun removeSeededImages() {
        seededIds.forEach {
            resolver.delete(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                "_id = ?",
                arrayOf(it.toString()),
            )
        }
    }

    @Test
    fun mediaStoreSource_seeded250Images_pagesReturn250UniqueIds() {
        val pager = PhotoPager(ContentResolverMediaStoreSource(resolver))
        val seen = mutableListOf<String>()
        var cursor = ""
        do {
            val outcome =
                pager.page(
                    photoPage {
                        this.cursor = cursor
                        limit = 100
                    },
                    PhotoAccess.PHOTO_ACCESS_FULL,
                )
            val result = (outcome as PhotoPageOutcome.Page).result
            seen += result.itemsList.map { it.id }
            cursor = result.nextCursor
        } while (cursor.isNotEmpty())

        val seededStrings = seededIds.map { it.toString() }.toSet()
        assertEquals(SEED_COUNT, seen.filter { it in seededStrings }.toSet().size)
        assertEquals(seen.size, seen.toSet().size)
    }

    private companion object {
        const val SEED_COUNT = 250
        const val SEED_DATE_TAKEN = 1_700_000_000_000L
    }
}
