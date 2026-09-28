package dev.tandem.core.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

// E00-28 tdd:
//   unit: tandemActivity_onCreate_decorViewFiltersTouchesWhenObscured
@RunWith(AndroidJUnit4::class)
class TandemActivityTest {
    @Test
    fun tandemActivity_onCreate_decorViewFiltersTouchesWhenObscured() {
        val activity = Robolectric.buildActivity(TandemActivity::class.java).setup().get()

        assertTrue(activity.window.decorView.filterTouchesWhenObscured)
    }
}
