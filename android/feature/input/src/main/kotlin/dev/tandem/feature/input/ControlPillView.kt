package dev.tandem.feature.input

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.compose.ui.graphics.toArgb
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemRadii
import dev.tandem.core.designsystem.TandemSpacing

/**
 * The on-phone "Mac is controlling · Stop" pill (ui-spec §5.2, §9.5, §10 `control.pill`, invariant
 * 8): ink pill, signal dot, label and a white Stop button with a 48 dp touch target. Plain views so it
 * can live in an accessibility overlay window without a Compose host.
 */
@SuppressLint("ViewConstructor") // built in code for the overlay window, never inflated
class ControlPillView(
    context: Context,
    onStop: () -> Unit,
) : LinearLayout(context) {
    private val density = context.resources.displayMetrics.density

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        background = pill(TandemColors.ink.toArgb())
        setPaddingRelative(px(TandemSpacing.lg.value), 0, px(TandemSpacing.xs.value), 0)
        addView(signalDot())
        addView(label(context))
        addView(stopButton(context, onStop))
    }

    private fun signalDot() =
        View(context).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL }.also { it.setColor(SIGNAL) }
            layoutParams = LayoutParams(px(DOT_DP), px(DOT_DP)).apply { marginEnd = px(TandemSpacing.sm.value) }
        }

    private fun label(context: Context) =
        TextView(context).apply {
            text = context.getString(R.string.control_pill_label)
            setTextColor(TandemColors.paper.toArgb())
            textSize = TEXT_SP
            layoutParams =
                LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
                    .apply { marginEnd = px(TandemSpacing.md.value) }
        }

    private fun stopButton(
        context: Context,
        onStop: () -> Unit,
    ) = TextView(context).apply {
        text = context.getString(R.string.control_pill_stop)
        contentDescription = context.getString(R.string.control_pill_stop_description)
        setTextColor(TandemColors.ink.toArgb())
        textSize = TEXT_SP
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        minimumHeight = px(TandemSpacing.touchTarget.value)
        minimumWidth = px(TandemSpacing.touchTarget.value)
        setPadding(px(TandemSpacing.lg.value), 0, px(TandemSpacing.lg.value), 0)
        background = pill(TandemColors.paper.toArgb())
        isClickable = true
        setOnClickListener { onStop() }
    }

    private fun pill(color: Int) =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = px(TandemRadii.button.value).toFloat()
        }

    private fun px(dp: Float): Int = (dp * density).toInt()

    private fun px(dp: Int): Int = px(dp.toFloat())

    private companion object {
        val SIGNAL = TandemColors.signal.toArgb()
        const val DOT_DP = 8
        const val TEXT_SP = 14f
    }
}
