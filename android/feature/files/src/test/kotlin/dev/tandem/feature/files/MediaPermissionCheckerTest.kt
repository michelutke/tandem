package dev.tandem.feature.files

import android.Manifest
import android.app.Application
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.photoPage
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
class MediaPermissionCheckerTest {
    private val application: Application = ApplicationProvider.getApplicationContext()

    @Test
    fun mediaPermission_api34_requestIncludesVisualUserSelected() {
        val permissions = MediaPermissionChecker(application, sdkInt = 34).requiredPermissions()

        assertEquals(
            listOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            ),
            permissions,
        )
    }

    @Test
    fun mediaPermission_api33_requestsImagesAndVideoOnly() {
        val permissions = MediaPermissionChecker(application, sdkInt = 33).requiredPermissions()

        assertEquals(listOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO), permissions)
    }

    @Test
    @Config(sdk = [34])
    fun mediaPermission_onlyUserSelectedGranted_mapsToPartial() {
        shadowOf(application).grantPermissions(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)

        assertEquals(PhotoAccess.PHOTO_ACCESS_PARTIAL, MediaPermissionChecker(application, sdkInt = 34).access())
    }

    @Test
    @Config(sdk = [34])
    fun mediaPermission_imagesGranted_mapsToFull() {
        shadowOf(application).grantPermissions(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        )

        assertEquals(PhotoAccess.PHOTO_ACCESS_FULL, MediaPermissionChecker(application, sdkInt = 34).access())
    }

    @Test
    @Config(sdk = [34])
    fun mediaPermission_nothingGranted_mapsToNone() {
        assertEquals(PhotoAccess.PHOTO_ACCESS_NONE, MediaPermissionChecker(application, sdkInt = 34).access())
    }

    @Test
    @Config(sdk = [34])
    fun mediaPermission_nothingGranted_pageReturnsZeroItemsAccessNone() {
        val checker = MediaPermissionChecker(application, sdkInt = 34)
        val responder = PhotoPageResponder(checker, PhotoPager { _, _ -> error("must not query") })

        val result = (responder.respond(photoPage { limit = 100 }) as PhotoPageOutcome.Page).result

        assertEquals(0, result.itemsCount)
        assertEquals(PhotoAccess.PHOTO_ACCESS_NONE, result.access)
    }
}
