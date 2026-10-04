package dev.tandem.feature.mirror

data class EncoderSize(
    val width: Int,
    val height: Int,
)

/** Plans encoder dimensions for a display geometry (E61-05): long edge ≤ 1920, aspect preserved, even values. */
object RotationPlanner {
    private const val MAX_LONG_EDGE = 1920

    fun plan(
        displayWidth: Int,
        displayHeight: Int,
    ): EncoderSize {
        val longEdge = maxOf(displayWidth, displayHeight)
        if (longEdge <= MAX_LONG_EDGE) {
            return EncoderSize(displayWidth.roundDownToEven(), displayHeight.roundDownToEven())
        }
        return EncoderSize(
            scale(displayWidth, longEdge).roundDownToEven(),
            scale(displayHeight, longEdge).roundDownToEven(),
        )
    }

    /** Plan for the same display after a 90 degree rotation. */
    fun rotate(
        displayWidth: Int,
        displayHeight: Int,
    ): EncoderSize = plan(displayHeight, displayWidth)

    private fun scale(
        edge: Int,
        longEdge: Int,
    ): Int = (edge.toLong() * MAX_LONG_EDGE / longEdge).toInt()

    private fun Int.roundDownToEven(): Int = this and 1.inv()
}
