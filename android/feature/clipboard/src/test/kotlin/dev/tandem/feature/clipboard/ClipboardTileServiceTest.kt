package dev.tandem.feature.clipboard

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

// E31-12 tdd:
//   unit: clipboardTile_click_startsTransparentCaptureActivity
@RunWith(AndroidJUnit4::class)
class ClipboardTileServiceTest {
    @Test
    fun clipboardTile_click_startsTransparentCaptureActivity() {
        val service = Robolectric.buildService(ClipboardTileService::class.java).get()
        val started = mutableListOf<Intent>()
        service.activityLauncher = { started += it }

        service.onClick()

        assertEquals(ClipboardCaptureActivity::class.java.name, started.single().component?.className)
    }
}
