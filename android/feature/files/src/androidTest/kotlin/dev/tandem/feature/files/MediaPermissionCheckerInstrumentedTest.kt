package dev.tandem.feature.files

import android.Manifest
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.PhotoAccess
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

// E41-02 tdd: instrumented: mediaPermission_pmGrantUserSelectedOnlyApi35_reportsPartial
// Runs on the api35 managed device (E00-21): grants only USER_SELECTED via `pm grant`.
@RunWith(AndroidJUnit4::class)
class MediaPermissionCheckerInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test
    fun mediaPermission_pmGrantUserSelectedOnlyApi35_reportsPartial() {
        listOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO).forEach { pm("revoke", it) }
        pm("grant", Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)

        assertEquals(PhotoAccess.PHOTO_ACCESS_PARTIAL, MediaPermissionChecker(context).access())
    }

    private fun pm(
        action: String,
        permission: String,
    ) {
        instrumentation.uiAutomation
            .executeShellCommand("pm $action ${context.packageName} $permission")
            .close()
    }
}
