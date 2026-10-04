package dev.tandem.feature.files

import android.Manifest
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.PhotoAccess
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

// E41-02 tdd: instrumented: mediaPermission_pmGrantUserSelectedOnlyApi35_reportsPartial
// Runs on the api35 managed device (E00-21): grants only USER_SELECTED via `pm grant`. The androidTest
// manifest strips READ_MEDIA_IMAGES/VIDEO, so nothing is revoked (a revoke kills the test process).
@RunWith(AndroidJUnit4::class)
class MediaPermissionCheckerInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    fun mediaPermission_pmGrantUserSelectedOnlyApi35_reportsPartial() {
        pm("grant", Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)

        assertEquals(PhotoAccess.PHOTO_ACCESS_PARTIAL, MediaPermissionChecker(context).access())
    }

    private fun pm(
        action: String,
        permission: String,
    ) {
        // Drain the output so the command has finished before the checker reads the grants.
        val output = instrumentation.uiAutomation.executeShellCommand("pm $action ${context.packageName} $permission")
        ParcelFileDescriptor.AutoCloseInputStream(output).use { it.readBytes() }
    }
}
