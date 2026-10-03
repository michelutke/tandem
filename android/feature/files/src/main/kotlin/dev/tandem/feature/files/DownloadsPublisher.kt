package dev.tandem.feature.files

import android.content.ContentResolver
import android.content.ContentValues
import android.provider.MediaStore
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream

/** Publishes a verified file into `Download/Tandem/`; never overwrites an existing entry (E40-05). */
fun interface DownloadsPublisher {
    @Throws(IOException::class)
    fun publish(
        name: String,
        mime: String,
        content: InputStream,
    )
}

/**
 * MediaStore [DownloadsPublisher]: inserts with `IS_PENDING=1`, copies, then clears the flag so no
 * partial entry is ever visible. MediaStore suffixes colliding names itself.
 */
class MediaStoreDownloadsPublisher(
    private val contentResolver: ContentResolver,
) : DownloadsPublisher {
    override fun publish(
        name: String,
        mime: String,
        content: InputStream,
    ) {
        val pending =
            ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime.ifEmpty { FALLBACK_MIME })
                put(MediaStore.Downloads.RELATIVE_PATH, RELATIVE_PATH)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
        val uri =
            contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, pending)
                ?: throw IOException("insert failed")
        try {
            val output = contentResolver.openOutputStream(uri) ?: throw FileNotFoundException()
            output.use { content.copyTo(it) }
            val published = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            contentResolver.update(uri, published, null, null)
        } catch (e: IOException) {
            contentResolver.delete(uri, null, null)
            throw e
        }
    }

    private companion object {
        const val RELATIVE_PATH = "Download/Tandem/"
        const val FALLBACK_MIME = "application/octet-stream"
    }
}
