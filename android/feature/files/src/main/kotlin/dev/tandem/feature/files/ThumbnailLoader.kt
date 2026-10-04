package dev.tandem.feature.files

import android.graphics.Bitmap
import java.io.FileNotFoundException

/**
 * Seam over `ContentResolver.loadThumbnail`. Throws [FileNotFoundException] for a missing id and
 * [SecurityException] for an id outside the current media grant.
 */
fun interface ThumbnailLoader {
    fun load(
        id: Long,
        sizePx: Int,
    ): Bitmap
}
