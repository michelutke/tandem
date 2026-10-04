package dev.tandem.feature.input

sealed interface MappingResult

data class Mapped(
    val x: Float,
    val y: Float,
) : MappingResult

data class Dropped(
    val reason: DropReason,
) : MappingResult

enum class DropReason { InvalidSize, OutsideWindow, OutsideContent }

data class Size(
    val width: Int,
    val height: Int,
) {
    val isValid: Boolean get() = width > 0 && height > 0

    fun contains(
        x: Float,
        y: Float,
    ): Boolean = x >= 0f && y >= 0f && x < width && y < height
}

/** Clockwise rotation between the stream orientation and the current display rotation. */
enum class RotationDelta { None, Rotate90, Rotate180, Rotate270 }

/** Maps a Mac mirror-window point to a device screen point; never clamps (F-9.3, E62-03). */
object CoordinateMapper {
    fun map(
        windowX: Float,
        windowY: Float,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta = RotationDelta.None,
    ): MappingResult =
        when {
            !window.isValid || !display.isValid -> Dropped(DropReason.InvalidSize)
            !window.contains(windowX, windowY) -> Dropped(DropReason.OutsideWindow)
            else -> mapInsideWindow(windowX, windowY, window, display, rotationDelta)
        }

    private fun mapInsideWindow(
        windowX: Float,
        windowY: Float,
        window: Size,
        display: Size,
        rotationDelta: RotationDelta,
    ): MappingResult {
        val scale = minOf(window.width.toFloat() / display.width, window.height.toFloat() / display.height)
        val contentX = windowX - (window.width - display.width * scale) / 2f
        val contentY = windowY - (window.height - display.height * scale) / 2f
        val insideContent =
            contentX >= 0f && contentY >= 0f && contentX < display.width * scale && contentY < display.height * scale
        if (!insideContent) return Dropped(DropReason.OutsideContent)
        return rotate(contentX / scale, contentY / scale, display, rotationDelta)
    }

    private fun rotate(
        x: Float,
        y: Float,
        display: Size,
        rotationDelta: RotationDelta,
    ): Mapped =
        when (rotationDelta) {
            RotationDelta.None -> Mapped(x, y)
            RotationDelta.Rotate90 -> Mapped(y, display.width - x)
            RotationDelta.Rotate180 -> Mapped(display.width - x, display.height - y)
            RotationDelta.Rotate270 -> Mapped(display.height - y, x)
        }
}
