package dev.tandem.feature.input

import dev.tandem.protocol.v1.Scroll
import dev.tandem.protocol.v1.Swipe
import dev.tandem.protocol.v1.Tap

/**
 * Translates Tap/Swipe/Scroll into one stroke after [CoordinateMapper]; any Dropped mapping dispatches
 * nothing and is never clamped. Not reachable from transport/session code; the invariant 8 authorization
 * gate (E62-06) must wrap every call. Never logs coordinates.
 */
class GestureTranslator(
    private val actions: AccessibilityActions,
) {
    fun handle(
        tap: Tap,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta = RotationDelta.None,
    ): InputResult {
        val point = map(tap.x, tap.y, window, display, rotationDelta) ?: return InputResult.NoOp
        return dispatch(GestureStroke(point.x, point.y, point.x, point.y, TAP_DURATION_MS))
    }

    fun handle(
        swipe: Swipe,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta = RotationDelta.None,
    ): InputResult {
        if (swipe.durationMs !in SWIPE_DURATION_RANGE_MS) return InputResult.NoOp
        return dispatchBetween(
            map(swipe.x1, swipe.y1, window, display, rotationDelta),
            map(swipe.x2, swipe.y2, window, display, rotationDelta),
            swipe.durationMs.toLong(),
        )
    }

    /** Positive dy moves the stroke upward (content scrolls down); dx follows the same inversion. */
    fun handle(
        scroll: Scroll,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta = RotationDelta.None,
    ): InputResult =
        dispatchBetween(
            map(scroll.x, scroll.y, window, display, rotationDelta),
            mapWindowPoint(
                scroll.x.toUnsignedFloat() - scroll.dx,
                scroll.y.toUnsignedFloat() - scroll.dy,
                window,
                display,
                rotationDelta,
            ),
            SCROLL_DURATION_MS,
        )

    private fun dispatchBetween(
        start: Mapped?,
        end: Mapped?,
        durationMs: Long,
    ): InputResult =
        if (start == null || end == null) {
            InputResult.NoOp
        } else {
            dispatch(GestureStroke(start.x, start.y, end.x, end.y, durationMs))
        }

    private fun map(
        x: Int,
        y: Int,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta,
    ): Mapped? = mapWindowPoint(x.toUnsignedFloat(), y.toUnsignedFloat(), window, display, rotationDelta)

    private fun mapWindowPoint(
        x: Float,
        y: Float,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta,
    ): Mapped? = CoordinateMapper.map(x, y, window, display, rotationDelta) as? Mapped

    private fun dispatch(stroke: GestureStroke): InputResult =
        if (actions.dispatchGesture(stroke)) InputResult.Performed else InputResult.NoOp

    private fun Int.toUnsignedFloat(): Float = Integer.toUnsignedLong(this).toFloat()

    private companion object {
        const val TAP_DURATION_MS = 50L
        const val SCROLL_DURATION_MS = 300L
        val SWIPE_DURATION_RANGE_MS = 1..5000
    }
}
