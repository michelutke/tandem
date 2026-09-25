package dev.tandem.core.designsystem

import android.provider.Settings
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp

// Motion specs (ui-spec.md §4). Springs, not durations: every component builds its animation
// through `tandemAnimateFloatAsState` / `tandemAnimateDpAsState` below so "Remove animations"
// (§4, E00-31 acceptance) is honoured in exactly one place.
object TandemMotion {
    /** #01 Home ring / activity chart: spring, low stiffness. */
    val ringSpring: FiniteAnimationSpec<Float> =
        spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessLow)
    const val RING_STAGGER_MILLIS = 600

    /** #02 M3E switch: Material spatial spring, fast. */
    val switchSpring: FiniteAnimationSpec<Float> =
        spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow)

    /** #03 Floating toolbar selection pill / #04 Cookie FAB shape-morph: M3 Expressive defaults. */
    val toolbarSpring: FiniteAnimationSpec<Float> =
        spring(dampingRatio = Spring.DampingRatioLowBouncy, stiffness = Spring.StiffnessMedium)
    val cookieFabSpring: FiniteAnimationSpec<Float> =
        spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)

    /** #06 Find phone: pulse loop. */
    const val FIND_PHONE_PULSE_MILLIS = 1200

    /** #07 Pairing countdown: last 10 s the numeral turns grey -> red, no easing (a step, not a spring). */
    const val PAIRING_COUNTDOWN_RED_THRESHOLD_SECONDS = 10
}

/**
 * True when the platform "Remove animations" developer/accessibility setting is on
 * (`Settings.Global.ANIMATOR_DURATION_SCALE == 0`). Every Tandem component reads this through
 * [tandemAnimateFloatAsState] / [tandemAnimateDpAsState] rather than animating directly.
 */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/**
 * `animateFloatAsState` that replaces [spec] with an instant [snap] when [reduceMotion] (defaults
 * to [rememberReduceMotion]) is on, per ui-spec.md §4 ("state changes become instant").
 */
@Composable
fun tandemAnimateFloatAsState(
    targetValue: Float,
    spec: FiniteAnimationSpec<Float> = TandemMotion.ringSpring,
    reduceMotion: Boolean = rememberReduceMotion(),
    label: String = "TandemAnimatedFloat",
): State<Float> {
    val effectiveSpec: FiniteAnimationSpec<Float> = if (reduceMotion) snap() else spec
    return animateFloatAsState(targetValue = targetValue, animationSpec = effectiveSpec, label = label)
}

/** [Dp] counterpart of [tandemAnimateFloatAsState]. */
@Composable
fun tandemAnimateDpAsState(
    targetValue: Dp,
    spec: FiniteAnimationSpec<Dp> = spring(),
    reduceMotion: Boolean = rememberReduceMotion(),
    label: String = "TandemAnimatedDp",
): State<Dp> {
    val effectiveSpec: FiniteAnimationSpec<Dp> = if (reduceMotion) snap() else spec
    return animateDpAsState(targetValue = targetValue, animationSpec = effectiveSpec, label = label)
}
