package dev.tandem.companion

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/**
 * E62-08: the foreground "counting test activity" for the input-authorization mitm-lab scenarios.
 * Counts every touch gesture start that reaches it (an injected gesture is indistinguishable from a
 * real touch here) and logs only the running count as `TandemInputCounter down=<n>`, never a
 * coordinate or typed text. The focused [EditText] is where a `SetText` event would land. Started
 * with `adb shell am start -n dev.tandem.companion/.InputCounterActivity`. Deliberately a plain
 * [Activity]: `TandemActivity`'s obscured-touch filter would drop gestures under the on-phone
 * indicator overlay and make a "zero injected" count pass for the wrong reason.
 */
@Suppress("TandemActivityBase")
class InputCounterActivity : Activity() {
    private var downCount = 0
    private lateinit var counterView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        counterView = TextView(this).apply { text = counterText() }
        val input = EditText(this).apply { contentDescription = INPUT_DESCRIPTION }
        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                addView(counterView, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                addView(input, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            },
        )
        Log.i(TAG, "ready down=$downCount")
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            downCount++
            counterView.text = counterText()
            Log.i(TAG, "down=$downCount")
        }
        return super.dispatchTouchEvent(event)
    }

    private fun counterText() = "touches: $downCount"

    private companion object {
        const val TAG = "TandemInputCounter"
        const val INPUT_DESCRIPTION = "input-target"
    }
}
