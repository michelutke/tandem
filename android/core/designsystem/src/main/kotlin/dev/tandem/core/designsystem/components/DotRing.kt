@file:Suppress("UnusedPrivateMember", "MagicNumber") // @Preview composables (E00-31); ring geometry tables

package dev.tandem.core.designsystem.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemMotion
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.drawRingDots
import dev.tandem.core.designsystem.rememberReduceMotion
import dev.tandem.core.designsystem.tandemAnimateFloatAsState
import kotlin.math.roundToInt

private val RING_DOT_COUNTS = intArrayOf(72, 64, 56)
private val RING_RADIUS_FRACTIONS = floatArrayOf(0.94f, 0.85f, 0.76f)
private const val RING_DOT_RADIUS_DIVISOR = 90f
private const val INNER_CONTENT_FRACTION = 0.56f
private const val PULSE_BASE_ALPHA = 0.12f
private const val PULSE_PEAK_ALPHA = 0.5f
private val MIN_NUMERAL_SIZE = 24.sp

/**
 * The home ring (ui-spec.md §5.2, §6): three concentric dot rings around a big [numeral] with its
 * small grey [numeralUnit] bottom-aligned next to it and a [label] below. Dots light clockwise
 * from the top up to [litFraction] (motion #01), the dot at [signalFraction] (default: the lit
 * arc's leading dot) is signal green. [pulse] makes the unlit rings pulse outward (motion #06) and
 * stops under "Remove animations". The numeral shrinks to fit at large font scales (ui-spec §3.2).
 * [onDark] draws on a dark surface; [signalInnerRing] lights the innermost ring signal green (ringing).
 * One TalkBack description carries numeral, unit and label, since the dots are decorative.
 */
@Composable
@Suppress("LongParameterList") // slot-style component with several independent optional knobs
fun DotRing(
    numeral: String,
    label: String,
    modifier: Modifier = Modifier,
    numeralUnit: String? = null,
    litFraction: Float = 0f,
    signalFraction: Float? = null,
    pulse: Boolean = false,
    diameter: Dp = 240.dp,
    onDark: Boolean = false,
    signalInnerRing: Boolean = false,
) {
    val animatedFraction by tandemAnimateFloatAsState(targetValue = litFraction.coerceIn(0f, 1f))
    val pulsePhase = rememberPulsePhase(pulse)
    val litInk = if (onDark) TandemColors.inkOnDark else TandemColors.ink
    val description =
        listOf((numeral + (numeralUnit ?: "")).trim(), label).filter { it.isNotEmpty() }.joinToString(", ")

    Box(
        modifier = modifier.size(diameter).clearAndSetSemantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            RING_DOT_COUNTS.forEachIndexed { ring, dotCount ->
                val allSignal = signalInnerRing && ring == 0
                val lit = if (allSignal) dotCount else (animatedFraction * dotCount).roundToInt()
                val signal = signalFraction?.let { (it * dotCount).roundToInt() % dotCount } ?: (lit - 1)
                drawRingDots(
                    dotCount = dotCount,
                    litDots = lit,
                    ringRadius = size.minDimension / 2f * RING_RADIUS_FRACTIONS[ring] * 0.98f,
                    dotRadius = size.minDimension / RING_DOT_RADIUS_DIVISOR,
                    signalIndex =
                        if (allSignal) {
                            -1
                        } else if (ring == 0 || signalFraction != null) {
                            signal
                        } else {
                            null
                        },
                    unlitColor = unlitColor(pulsePhase?.value, ring, onDark),
                    litColor = if (allSignal) TandemColors.signal else litInk,
                )
            }
        }
        RingCenter(numeral, numeralUnit, label, Modifier.widthIn(max = diameter * INNER_CONTENT_FRACTION))
    }
}

@Composable
private fun RingCenter(
    numeral: String,
    numeralUnit: String?,
    label: String,
    modifier: Modifier,
) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        if (numeral.isNotEmpty()) {
            Row(verticalAlignment = Alignment.Bottom) {
                BasicText(
                    text = numeral,
                    style = TandemType.displayNumeral,
                    maxLines = 1,
                    color = { TandemColors.ink },
                    autoSize = TextAutoSize.StepBased(minFontSize = MIN_NUMERAL_SIZE, maxFontSize = 80.sp),
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (numeralUnit != null) {
                    Text(
                        text = numeralUnit,
                        style = TandemType.meta,
                        color = TandemColors.ink2,
                        modifier = Modifier.padding(start = TandemSpacing.xs, bottom = TandemSpacing.md),
                    )
                }
            }
        }
        Text(
            text = label,
            style = TandemType.meta,
            color = TandemColors.ink,
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
    }
}

@Composable
private fun rememberPulsePhase(pulse: Boolean): State<Float>? {
    if (!pulse || rememberReduceMotion()) return null
    return rememberInfiniteTransition(label = "DotRingPulse").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(TandemMotion.FIND_PHONE_PULSE_MILLIS, easing = LinearEasing),
                repeatMode = RepeatMode.Restart,
            ),
        label = "DotRingPulsePhase",
    )
}

private fun unlitColor(
    phase: Float?,
    ring: Int,
    onDark: Boolean,
): Color {
    val base = if (onDark) TandemColors.inkOnDark else TandemColors.ink
    if (phase == null) return if (onDark) base.copy(alpha = PULSE_BASE_ALPHA) else TandemColors.lineUnlitDot
    val rings = RING_DOT_COUNTS.size
    val intensity = 1f - ((phase - ring.toFloat() / rings + 1f) % 1f)
    return base.copy(alpha = PULSE_BASE_ALPHA + (PULSE_PEAK_ALPHA - PULSE_BASE_ALPHA) * intensity)
}

@Preview(showBackground = true)
@Composable
private fun DotRingIdlePreview() {
    DotRing(numeral = "43", numeralUnit = "%", label = "Sending to Mac", litFraction = 0.43f)
}
