package dev.tandem.feature.files

import android.Manifest
import android.content.ContentValues
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.PhotoErrorReason
import dev.tandem.protocol.v1.photoPage
import dev.tandem.protocol.v1.thumbRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

// E41-08 tdd: instrumented: partialAccess_unselectedSeededId_thumbAccessDenied
// E41-08 tdd: instrumented: pagingCorrectness_seeded500Images_exactly500UniqueIdsInFivePages
// Runs on the api35 managed device (E00-21): the androidTest manifest strips READ_MEDIA_IMAGES/VIDEO so
// the process starts without them, and the unselected image is inserted through the shell uid.
@RunWith(AndroidJUnit4::class)
class PartialAccessPagingInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val resolver = context.contentResolver
    private val seededIds = mutableListOf<Long>()
    private val shellInsertedIds = mutableListOf<Long>()
    private val namePrefix = "$NAME_PREFIX-${UUID.randomUUID()}"

    @After
    fun removeSeededImages() {
        resolver.delete(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            "${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?",
            arrayOf("$namePrefix%"),
        )
        shellInsertedIds.forEach { shell("content delete --uri $IMAGES_URI --where _id=$it") }
        shellInsertedIds.clear()
        seededIds.clear()
    }

    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    fun partialAccess_unselectedSeededId_thumbAccessDenied() =
        runBlocking {
            val unselectedId = insertThroughShell("$namePrefix-unselected.jpg")
            pm("grant", Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)

            val page =
                PhotoPageResponder(
                    MediaPermissionChecker(context),
                    PhotoPager(ContentResolverMediaStoreSource(resolver)),
                ).respond(photoPage { limit = 100 })
            val thumb =
                ThumbnailResponder(ContentResolverThumbnailLoader(resolver), Dispatchers.IO)
                    .respond(thumbRequest { id = unselectedId.toString() })

            assertEquals(PhotoAccess.PHOTO_ACCESS_PARTIAL, (page as PhotoPageOutcome.Page).result.access)
            assertEquals(
                PhotoErrorReason.PHOTO_ERROR_REASON_ACCESS_DENIED,
                (thumb as ThumbOutcome.Failure).error.reason,
            )
        }

    @Test
    fun pagingCorrectness_seeded500Images_exactly500UniqueIdsInFivePages() {
        seedImages()
        val pager = PhotoPager(ContentResolverMediaStoreSource(resolver))
        val seen = mutableListOf<String>()
        var pages = 0
        var cursor = ""
        do {
            val result =
                (
                    pager.page(
                        photoPage {
                            this.cursor = cursor
                            limit = PAGE_LIMIT
                        },
                        PhotoAccess.PHOTO_ACCESS_FULL,
                    ) as PhotoPageOutcome.Page
                ).result
            seen += result.itemsList.map { it.id }
            pages++
            cursor = result.nextCursor
        } while (cursor.isNotEmpty())

        val seededStrings = seededIds.map { it.toString() }
        assertEquals(seededStrings.toSet(), seen.filter { it in seededStrings }.toSet())
        assertEquals(SEED_COUNT, seen.count { it in seededStrings })
        assertEquals(seen.size, seen.toSet().size)
        assertTrue(pages >= SEED_COUNT / PAGE_LIMIT)
    }

    private fun seedImages() {
        repeat(SEED_COUNT) { index ->
            val values =
                ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, "$namePrefix-$index.jpg")
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(MediaStore.Images.Media.DATE_TAKEN, SEED_DATE_TAKEN + index / 5)
                    put(MediaStore.Images.Media.WIDTH, 64)
                    put(MediaStore.Images.Media.HEIGHT, 48)
                }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            seededIds += requireNotNull(uri).lastPathSegment!!.toLong()
        }
    }

    private fun insertThroughShell(displayName: String): Long {
        shell(
            "content insert --uri $IMAGES_URI --bind _display_name:s:$displayName " +
                "--bind mime_type:s:image/jpeg --bind datetaken:l:$SEED_DATE_TAKEN",
        )
        val output = shell("content query --uri $IMAGES_URI --projection _id:_display_name")
        val id =
            output
                .lineSequence()
                .filter { it.contains("_display_name=$displayName") }
                .mapNotNull { ID_PATTERN.find(it) }
                .map { it.groupValues[1].toLong() }
                .lastOrNull()
        assertTrue("shell insert of $displayName not found: ${output.take(300)}", id != null)
        shellInsertedIds += id!!
        writeThroughShell("$IMAGES_URI/$id", SEED_BYTES)
        shell("content update --uri $IMAGES_URI/$id --bind is_pending:i:0")
        return id
    }

    private fun pm(
        action: String,
        permission: String,
    ) {
        shell("pm $action ${context.packageName} $permission")
    }

    private fun writeThroughShell(
        uri: String,
        bytes: ByteArray,
    ) {
        val (stdout, stdin) = instrumentation.uiAutomation.executeShellCommandRw("content write --uri $uri")
        ParcelFileDescriptor.AutoCloseOutputStream(stdin).use { it.write(bytes) }
        ParcelFileDescriptor.AutoCloseInputStream(stdout).use { it.readBytes() }
    }

    private fun shell(command: String): String =
        ParcelFileDescriptor
            .AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command))
            .use { it.readBytes().decodeToString() }

    private companion object {
        val ID_PATTERN = Regex("_id=(\\d+)")
        const val SEED_COUNT = 500
        const val PAGE_LIMIT = 100
        const val SEED_DATE_TAKEN = 1_700_000_000_000L
        val SEED_BYTES = "x".encodeToByteArray()
        const val NAME_PREFIX = "tandem-e41-08"
        const val IMAGES_URI = "content://media/external/images/media"
    }
}
