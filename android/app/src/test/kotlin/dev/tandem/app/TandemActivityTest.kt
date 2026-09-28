package dev.tandem.app

import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.ui.TandemActivity
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

// E00-28 tdd:
//   unit: everyDeclaredActivity_extendsTandemActivity
//
// tandemActivity_onCreate_decorViewFiltersTouchesWhenObscured moved to
// core/ui/src/test/kotlin/dev/tandem/core/ui/TandemActivityTest.kt in E31-06, alongside the class
// itself.
@RunWith(AndroidJUnit4::class)
class TandemActivityTest {
    /**
     * Closed-form backstop for the `TandemActivityBase` detekt rule (which only sees the source
     * file being linted, and has documented syntactic blind spots — a `typealias`, an unrelated
     * type sharing one of the flagged names, ...): reads every `<activity>` this app module's own
     * source declares in its merged manifest (Robolectric's [RuntimeEnvironment.getApplication]
     * resolves against the real, debug-variant-merged `AndroidManifest.xml`, reused by local unit
     * tests via `testOptions.unitTests.isIncludeAndroidResources`) and asserts each one really is
     * assignable to [TandemActivity] at the class level, not just by source-text pattern matching.
     *
     * Filtered to the `dev.tandem.` package prefix: the debug variant's merged manifest also
     * carries a library-injected `androidx.activity.ComponentActivity` entry (from
     * `androidx-compose-ui-test-manifest`, used to host Compose UI tests) that is neither ours nor
     * release-visible, so it is out of scope for this assertion.
     */
    @Test
    fun everyDeclaredActivity_extendsTandemActivity() {
        val context = RuntimeEnvironment.getApplication()
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_ACTIVITIES)
        val activityInfos = packageInfo.activities.orEmpty().filter { it.name.startsWith("dev.tandem.") }

        assertTrue(
            "expected at least one dev.tandem.* <activity> in the merged manifest to check",
            activityInfos.isNotEmpty(),
        )
        activityInfos.forEach { activityInfo ->
            val activityClass = Class.forName(activityInfo.name)
            assertTrue(
                "${activityInfo.name} must extend TandemActivity",
                TandemActivity::class.java.isAssignableFrom(activityClass),
            )
        }
    }
}
