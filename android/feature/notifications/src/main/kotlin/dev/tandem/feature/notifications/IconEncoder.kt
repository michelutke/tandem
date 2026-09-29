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

    fun encode(drawable: Drawable): ByteArray {
        val bitmap = createBitmap(MAX_DIMENSION, MAX_DIMENSION)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, MAX_DIMENSION, MAX_DIMENSION)
        drawable.draw(canvas)
        return ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, PNG_QUALITY, stream)
            stream.toByteArray()
        }
    }

    private const val PNG_QUALITY = 100
}
