package dev.tandem.feature.files

import android.content.ContentResolver
import android.content.ContentUris
import android.graphics.Bitmap
import android.provider.MediaStore
import android.util.Size
import dev.tandem.protocol.v1.PhotoAccess
import java.io.FileNotFoundException

/**
 * Real [ThumbnailLoader] over MediaStore images. Under partial access MediaStore hides unselected
 * items as not found, so a miss there is reported as a denied grant.
 */
class ContentResolverThumbnailLoader(
    private val contentResolver: ContentResolver,
    private val access: () -> PhotoAccess = { PhotoAccess.PHOTO_ACCESS_FULL },
) : ThumbnailLoader {
    override fun load(
        id: Long,
        sizePx: Int,
    ): Bitmap {
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
        return try {
            contentResolver.loadThumbnail(uri, Size(sizePx, sizePx), null)
        } catch (e: FileNotFoundException) {
            if (access() == PhotoAccess.PHOTO_ACCESS_PARTIAL) throw SecurityException("item outside media grant", e)
            throw e
        }
    }
}
