package dev.tandem.feature.files

import android.content.ContentResolver
import android.content.ContentUris
import android.graphics.Bitmap
import android.provider.MediaStore
import android.util.Size

/** Real [ThumbnailLoader] over MediaStore images. */
class ContentResolverThumbnailLoader(
    private val contentResolver: ContentResolver,
) : ThumbnailLoader {
    override fun load(
        id: Long,
        sizePx: Int,
    ): Bitmap {
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
        return contentResolver.loadThumbnail(uri, Size(sizePx, sizePx), null)
    }
}
