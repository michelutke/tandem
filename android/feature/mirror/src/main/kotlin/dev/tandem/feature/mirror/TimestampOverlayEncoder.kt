package dev.tandem.feature.mirror

/**
 * Burns a frame index and phone-side wall clock into a luma frame as a row of 8x8 px cells (E61-08):
 * 32 bits of frame index then 64 bits of clock milliseconds, MSB first, white for 1 and black for 0, at
 * the top-left. The macOS decoder reads the same layout (`TimestampOverlayDecoder`).
 */
object TimestampOverlayEncoder {
    const val CELL_SIZE = 8
    const val FRAME_INDEX_BITS = 32
    const val CLOCK_BITS = 64
    const val TOTAL_BITS = FRAME_INDEX_BITS + CLOCK_BITS
    const val OVERLAY_WIDTH = TOTAL_BITS * CELL_SIZE

    private const val WHITE: Byte = -1

    fun render(
        frameIndex: Long,
        clockMs: Long,
        width: Int,
        height: Int,
    ): ByteArray = ByteArray(width * height).also { drawInto(it, width, frameIndex, clockMs) }

    fun drawInto(
        luma: ByteArray,
        width: Int,
        frameIndex: Long,
        clockMs: Long,
    ) {
        require(width >= OVERLAY_WIDTH && luma.size >= width * CELL_SIZE) { "frame too small for overlay" }
        for (bit in 0 until TOTAL_BITS) {
            val value = if (bitAt(bit, frameIndex, clockMs)) WHITE else 0
            for (row in 0 until CELL_SIZE) {
                luma.fill(value, row * width + bit * CELL_SIZE, row * width + (bit + 1) * CELL_SIZE)
            }
        }
    }

    private fun bitAt(
        bit: Int,
        frameIndex: Long,
        clockMs: Long,
    ): Boolean {
        val shifted =
            if (bit < FRAME_INDEX_BITS) {
                frameIndex shr (FRAME_INDEX_BITS - 1 - bit)
            } else {
                clockMs shr (TOTAL_BITS - 1 - bit)
            }
        return shifted and 1L == 1L
    }
}
