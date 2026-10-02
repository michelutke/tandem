package dev.tandem.feature.files

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class SelectMorePhotosNotifierTest {
    private val application: Application = ApplicationProvider.getApplicationContext()
    private val notifications = application.getSystemService(NotificationManager::class.java)

    private fun notifier() = SelectMorePhotosNotifier(application, MediaPermissionChecker(application, sdkInt = 34))

    @Test
    fun mediaPermission_partialAndMoreRequested_postsOneSelectMoreNotification() {
        shadowOf(application).grantPermissions(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)

        notifier().onMoreRequested()
        notifier().onMoreRequested()

        val posted = shadowOf(notifications).allNotifications
        assertEquals(1, posted.size)
        assertEquals(application.getString(R.string.select_more_photos_title), shadowOf(posted.single()).contentTitle)
    }

    @Test
    fun mediaPermission_partialNotificationTap_launchesPermissionRequest() {
        shadowOf(application).grantPermissions(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)

        notifier().onMoreRequested()

        val tap = shadowOf(shadowOf(notifications).allNotifications.single().contentIntent)
        assertTrue(tap.isActivity)
        assertEquals(MediaPermissionRequestActivity::class.java.name, tap.savedIntent.component?.className)
        assertTrue(tap.savedIntent.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
    }

    @Test
    fun mediaPermission_fullAccessAndMoreRequested_postsNothing() {
        shadowOf(application).grantPermissions(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        )

        notifier().onMoreRequested()

        assertEquals(0, shadowOf(notifications).allNotifications.size)
    }

    @Test
    fun mediaPermission_noAccessAndMoreRequested_postsNothing() {
        notifier().onMoreRequested()

        assertEquals(0, shadowOf(notifications).allNotifications.size)
    }
}
