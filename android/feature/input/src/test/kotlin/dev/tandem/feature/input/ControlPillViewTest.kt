package dev.tandem.feature.input

import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ControlPillViewTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun texts(pill: ControlPillView): List<TextView> =
        (0 until pill.childCount).mapNotNull { pill.getChildAt(it) as? TextView }

    @Test
    fun controlPill_shown_hasControllingLabelAndStop() {
        val labels = texts(ControlPillView(context) {}).map { it.text.toString() }

        assertEquals(listOf("Mac is controlling", "Stop"), labels)
    }

    @Test
    fun controlPill_stopTapped_callsOnStopOnce() {
        var stops = 0
        val pill = ControlPillView(context) { stops++ }

        texts(pill).last().performClick()

        assertEquals(1, stops)
    }

    @Test
    fun controlPill_stopButton_isAtLeast48dpTall() {
        val stop = texts(ControlPillView(context) {}).last()

        assertTrue(
            stop.minimumHeight >= 48 *
                context.resources.displayMetrics.density
                    .toInt(),
        )
    }
}
