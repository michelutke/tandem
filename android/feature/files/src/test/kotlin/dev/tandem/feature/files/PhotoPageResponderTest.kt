package dev.tandem.feature.files

import android.Manifest
import android.app.Application
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.PhotoErrorKind
import dev.tandem.protocol.v1.PhotoErrorReason
import dev.tandem.protocol.v1.photoPage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class PhotoPageResponderTest {
    private val application: Application = ApplicationProvider.getApplicationContext()
    private val rows = (1L..3L).map { MediaRow(id = it, dateTaken = it * 1000, width = 10, height = 10) }
    private val responder: PhotoPageResponder
        get() =
            PhotoPageResponder(
                MediaPermissionChecker(application, sdkInt = 34),
                PhotoPager { _, limit -> rows.reversed().take(limit) },
            )

    @Test
    fun photoPageResponder_fullAccess_returnsPageResult() {
        shadowOf(application).grantPermissions(Manifest.permission.READ_MEDIA_IMAGES)

        val outcome = responder.respond(photoPage { limit = 10 })

        val result = (outcome as PhotoPageOutcome.Page).result
        assertEquals(3, result.itemsCount)
        assertEquals(PhotoAccess.PHOTO_ACCESS_FULL, result.access)
    }

    @Test
    fun photoPageResponder_invalidCursor_returnsPhotoErrorNotPageResult() {
        shadowOf(application).grantPermissions(Manifest.permission.READ_MEDIA_IMAGES)

        val outcome = responder.respond(photoPage { cursor = "') OR 1=1 --" })

        val error = (outcome as PhotoPageOutcome.Failure).error
        assertEquals(PhotoErrorKind.PHOTO_ERROR_KIND_PAGE, error.kind)
        assertEquals(PhotoErrorReason.PHOTO_ERROR_REASON_INVALID_CURSOR, error.reason)
        assertTrue(error.ref.isNotEmpty())
    }
}
