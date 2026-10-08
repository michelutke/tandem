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
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

// Shared drawing for the dot motif (ui-spec.md §2 "Dot motif", §5.2 DotRing/DotChart/DotHero):
// lit = ink, unlit = ink at 12 %, current position = signal green.

/** A ring of dots, clockwise from the top; `litDots` (0..dotCount) are lit, the last one signals. */
internal fun DrawScope.drawRingDots(
    dotCount: Int,
    litDots: Int,
    ringRadius: Float = size.minDimension / 2f * 0.92f,
    dotRadius: Float = size.minDimension / 40f,
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
                litDots <= 0 -> TandemColors.lineUnlitDot
                index == litDots - 1 -> TandemColors.signal
                index < litDots -> TandemColors.ink
                else -> TandemColors.lineUnlitDot
            }
        drawCircle(color = color, radius = dotRadius, center = position)
    }
}

/** A single dot column, bottom-up, for [DotChart]'s per-period bars. */
internal fun DrawScope.drawColumnDots(
    maxDots: Int,
    litDots: Int,
    dotRadius: Float = size.width / 3f,
) {
    if (maxDots <= 0) return
    val spacing = size.height / maxDots
    for (index in 0 until maxDots) {
        val fromBottom = maxDots - 1 - index
        val center = Offset(size.width / 2f, spacing * index + spacing / 2f)
        val color = if (fromBottom < litDots) TandemColors.ink else TandemColors.lineUnlitDot
        drawCircle(color = color, radius = dotRadius, center = center)
    }
}

/** A decorative dot grid for the onboarding [DotHero]; purely visual, no meaning to convey. */
internal fun DrawScope.drawHeroDots(dotCount: Int) {
    if (dotCount <= 0) return
    val columns = ceil(sqrt(dotCount.toFloat())).toInt().coerceAtLeast(1)
    val rows = ceil(dotCount / columns.toFloat()).toInt().coerceAtLeast(1)
    val cellWidth = size.width / columns
    val cellHeight = size.height / rows
    val dotRadius = minOf(cellWidth, cellHeight) / 4f
    for (index in 0 until dotCount) {
        val column = index % columns
        val row = index / columns
        val center = Offset(cellWidth * column + cellWidth / 2f, cellHeight * row + cellHeight / 2f)
        drawCircle(color = TandemColors.ink, radius = dotRadius, center = center)
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
