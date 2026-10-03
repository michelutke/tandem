package dev.tandem.feature.contacts

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream

/**
 * Downsamples a contact photo to the wire thumbnail form (E51-01 cap): JPEG, longest edge
 * <= [MAX_EDGE_PX], <= [MAX_BYTES]. Undecodable input yields `null` (the contact still syncs).
 */
class ThumbnailScaler {
    fun scale(photoBytes: ByteArray): ByteArray? {
        if (photoBytes.isEmpty()) return null
        return decodeSampled(photoBytes)?.let { encodeWithinCap(scaleToMaxEdge(it)) }
    }

    private fun decodeSampled(photoBytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(photoBytes, 0, photoBytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options =
            BitmapFactory.Options().apply {
                inSampleSize = sampleSizeFor(maxOf(bounds.outWidth, bounds.outHeight))
            }
        return BitmapFactory.decodeByteArray(photoBytes, 0, photoBytes.size, options)
    }

    private fun sampleSizeFor(longestEdge: Int): Int {
        var sampleSize = 1
        while (longestEdge / (sampleSize * 2) >= MAX_EDGE_PX) sampleSize *= 2
        return sampleSize
    }

    private fun scaleToMaxEdge(bitmap: Bitmap): Bitmap {
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest <= MAX_EDGE_PX) return bitmap
        val ratio = MAX_EDGE_PX.toFloat() / longest
        val width = (bitmap.width * ratio).toInt().coerceAtLeast(1)
        val height = (bitmap.height * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }

    private fun encodeWithinCap(bitmap: Bitmap): ByteArray? =
        (START_QUALITY downTo MIN_QUALITY step QUALITY_STEP)
            .asSequence()
            .map { quality ->
                ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }
            }.firstOrNull { it.size() in 1..MAX_BYTES }
            ?.toByteArray()

    companion object {
        const val MAX_EDGE_PX = 96
        const val MAX_BYTES = 32768
        private const val START_QUALITY = 90
        private const val MIN_QUALITY = 20
        private const val QUALITY_STEP = 10
    }
}
