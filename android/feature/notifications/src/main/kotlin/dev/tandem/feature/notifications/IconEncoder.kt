package dev.tandem.feature.notifications

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import androidx.core.graphics.createBitmap
import java.io.ByteArrayOutputStream

/**
 * Encodes an app icon [Drawable] (as returned by `PackageManager.getApplicationIcon`, including an
 * `AdaptiveIconDrawable` on API 26+) to a flat PNG, sized to [MAX_DIMENSION] so the send side never
 * relies on the Mac's receive-side cap (E01-22, `IconCache.maxDimension`/`maxByteSize`) to reject an
 * oversized icon (E30-05).
 */
object IconEncoder {
    const val MAX_DIMENSION = 256

    /** The SPEC cap for the PNG of an `IconData` (docs/protocol/SPEC.md, notify channel caps). */
    const val MAX_PNG_BYTES = 64 * 1024

    private val FALLBACK_DIMENSIONS = listOf(MAX_DIMENSION, DIMENSION_192, DIMENSION_128, DIMENSION_96, DIMENSION_64)

    fun encode(drawable: Drawable): ByteArray = encodeWithinLimit { dimension -> encodeAt(drawable, dimension) }

    /** The first of [render] at [FALLBACK_DIMENSIONS] (largest first) within [MAX_PNG_BYTES], else the smallest. */
    internal fun encodeWithinLimit(render: (Int) -> ByteArray): ByteArray {
        var bytes = ByteArray(0)
        for (dimension in FALLBACK_DIMENSIONS) {
            bytes = render(dimension)
            if (bytes.size <= MAX_PNG_BYTES) break
        }
        return bytes
    }

    private fun encodeAt(
        drawable: Drawable,
        dimension: Int,
    ): ByteArray {
        val bitmap = createBitmap(dimension, dimension)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, dimension, dimension)
        drawable.draw(canvas)
        return ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, PNG_QUALITY, stream)
            stream.toByteArray()
        }
    }

    private const val PNG_QUALITY = 100
    private const val DIMENSION_192 = 192
    private const val DIMENSION_128 = 128
    private const val DIMENSION_96 = 96
    private const val DIMENSION_64 = 64
}
