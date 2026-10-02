package dev.tandem.app.clipboard

import android.content.ComponentName
import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

// E31-12 tdd:
//   ci: mergedManifest_captureActivityAndTile_notExportedAndBindPermissionRequired
@RunWith(AndroidJUnit4::class)
class ClipboardCaptureManifestTest {
    @Test
    fun mergedManifest_captureActivityAndTile_notExportedAndBindPermissionRequired() {
        val context = RuntimeEnvironment.getApplication()
        val activity =
            context.packageManager.getActivityInfo(
                ComponentName(context, "dev.tandem.feature.clipboard.ClipboardCaptureActivity"),
                PackageManager.GET_META_DATA,
            )
        val tile =
            context.packageManager.getServiceInfo(
                ComponentName(context, "dev.tandem.feature.clipboard.ClipboardTileService"),
                PackageManager.GET_META_DATA,
            )

        assertFalse(activity.exported)
        assertEquals("android.permission.BIND_QUICK_SETTINGS_TILE", tile.permission)
    }
}
