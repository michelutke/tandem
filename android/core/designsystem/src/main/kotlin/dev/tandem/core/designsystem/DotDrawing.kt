@file:Suppress("MagicNumber") // Geometry/ratio constants for the dot motif (ui-spec.md §2, §5.2).

package dev.tandem.core.designsystem

import androidx.compose.foundation.shape.GenericShape
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.toPath
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.graphics.shapes.Morph
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

// Shared drawing for the dot motif (ui-spec.md §2 "Dot motif", §5.2 DotRing/DotChart/DotHero):
// lit = ink, unlit = ink at 12 %, current position = signal green.

/**
 * A ring of dots, clockwise from the top; `litDots` (0..dotCount) are lit ink, the dot at
 * [signalIndex] (default: the last lit one) is signal green, the rest are unlit.
 */
@Suppress("LongParameterList") // geometry and colour knobs of one dot ring
internal fun DrawScope.drawRingDots(
    dotCount: Int,
    litDots: Int,
    ringRadius: Float = size.minDimension / 2f * 0.92f,
    dotRadius: Float = size.minDimension / 40f,
    signalIndex: Int? = litDots - 1,
    unlitColor: Color = TandemColors.lineUnlitDot,
    litColor: Color = TandemColors.ink,
) {
    val center = Offset(size.width / 2f, size.height / 2f)
    for (index in 0 until dotCount) {
        val angle = (2 * PI * index / dotCount) - PI / 2
        val position =
            Offset(
                x = center.x + ringRadius * cos(angle).toFloat(),
                y = center.y + ringRadius * sin(angle).toFloat(),
            )
        val color =
            when {
                index == signalIndex -> TandemColors.signal
                index < litDots -> litColor
                else -> unlitColor
            }
        drawCircle(color = color, radius = dotRadius, center = position)
    }
}

/** A single dot column, bottom-up, for [DotChart]'s per-period bars; [isCurrent] marks the top lit dot as signal. */
internal fun DrawScope.drawColumnDots(
    maxDots: Int,
    litDots: Int,
    isCurrent: Boolean = false,
    dotRadius: Float = size.width / 3f,
) {
    if (maxDots <= 0) return
    val spacing = size.height / maxDots
    for (index in 0 until maxDots) {
        val fromBottom = maxDots - 1 - index
        val center = Offset(size.width / 2f, spacing * index + spacing / 2f)
        val color =
            when {
                isCurrent && fromBottom == litDots - 1 -> TandemColors.signal
                fromBottom < litDots -> TandemColors.ink
                else -> TandemColors.lineUnlitDot
            }
        drawCircle(color = color, radius = dotRadius, center = center)
    }
}

private const val HERO_RADIUS_CELLS = 5.1f
private const val HERO_CORE_RADIUS_CELLS = 2.25f
private const val HERO_SIGNAL_OFFSET_CELLS = 3
private const val HERO_GRID = 11

/**
 * The decorative onboarding [DotHero]: a circular dot lattice with an ink core, grey outer dots
 * and one signal dot beside the core; purely visual, no meaning to convey.
 */
internal fun DrawScope.drawHeroDots() {
    val cell = size.minDimension / HERO_GRID
    val middle = HERO_GRID / 2
    for (row in 0 until HERO_GRID) {
        for (column in 0 until HERO_GRID) {
            val dx = column - middle
            val dy = row - middle
            val distance = sqrt((dx * dx + dy * dy).toFloat())
            if (distance > HERO_RADIUS_CELLS) continue
            val color =
                when {
                    dy == 0 && dx == HERO_SIGNAL_OFFSET_CELLS -> TandemColors.signal
                    distance <= HERO_CORE_RADIUS_CELLS -> TandemColors.ink
                    else -> TandemColors.lineUnlitDot
                }
            drawCircle(
                color = color,
                radius = cell * 0.18f,
                center = Offset(cell * column + cell / 2f, cell * row + cell / 2f),
            )
        }
    }
}

/** The 3x3 ink dot mark with a signal centre shown on the Paired screen (ui-spec §7.2). */
internal fun DrawScope.drawDotMark() {
    val cell = size.minDimension / 3f
    for (row in 0 until 3) {
        for (column in 0 until 3) {
            val isCentre = row == 1 && column == 1
            drawCircle(
                color = if (isCentre) TandemColors.signal else TandemColors.ink,
                radius = cell * 0.32f,
                center = Offset(cell * column + cell / 2f, cell * row + cell / 2f),
            )
        }
    }
}

/** The check mark shown inside the M3E switch thumb once it is on (ui-spec §4 motion #02). */
internal fun DrawScope.drawCheckMark(
    color: Color,
    strokeWidthFraction: Float = 0.16f,
) {
    val path =
        Path().apply {
            moveTo(size.width * 0.2f, size.height * 0.55f)
            lineTo(size.width * 0.42f, size.height * 0.75f)
            lineTo(size.width * 0.82f, size.height * 0.28f)
        }
    drawPath(
        path = path,
        color = color,
        style = Stroke(width = size.minDimension * strokeWidthFraction, cap = StrokeCap.Round, join = StrokeJoin.Round),
    )
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
private val cookieMorph by lazy {
    Morph(MaterialShapes.Cookie9Sided.normalized(), MaterialShapes.Circle.normalized())
}

/**
 * The M3E cookie outline flattening to a circle as [morph] goes from 0 to 1 (ui-spec §4 motion
 * #04: "Shape-morphs cookie -> circle on press"), via the platform `MaterialShapes` morph.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
internal fun cookieShape(morph: Float): Shape =
    GenericShape { size, _ ->
        val path = cookieMorph.toPath(morph.coerceIn(0f, 1f))
        path.transform(Matrix().apply { scale(size.width, size.height) })
        addPath(path)
    }
