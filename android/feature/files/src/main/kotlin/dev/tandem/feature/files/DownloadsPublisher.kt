package dev.tandem.feature.files

import android.content.ContentResolver
import android.content.ContentValues
import android.net.Uri
import android.provider.MediaStore
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream

/**
 * Publishes a verified file into `Download/Tandem/`; never overwrites an existing entry (E40-05).
 * Returns the content URI of the published entry.
 */
fun interface DownloadsPublisher {
    @Throws(IOException::class)
    fun publish(
        name: String,
        mime: String,
        content: InputStream,
    ): String
}

/**
 * MediaStore [DownloadsPublisher]: inserts with `IS_PENDING=1`, copies, then clears the flag so no
 * partial entry is ever visible. MediaStore suffixes colliding names itself.
 */
class MediaStoreDownloadsPublisher(
    private val contentResolver: ContentResolver,
) : DownloadsPublisher {
    @Suppress("TooGenericExceptionCaught") // any provider failure must delete the pending row
    override fun publish(
        name: String,
        mime: String,
        content: InputStream,
    ): String {
        val pending =
            ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime.ifEmpty { FALLBACK_MIME })
                put(MediaStore.Downloads.RELATIVE_PATH, RELATIVE_PATH)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
        val uri = insertPending(pending)
        try {
            val output = contentResolver.openOutputStream(uri) ?: throw FileNotFoundException()
            output.use { content.copyTo(it) }
            val published = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            contentResolver.update(uri, published, null, null)
            return uri.toString()
        } catch (e: IOException) {
            contentResolver.delete(uri, null, null)
            throw e
        } catch (e: RuntimeException) {
            contentResolver.delete(uri, null, null)
            throw IOException("publish failed", e)
        }
    }

    @Suppress("TooGenericExceptionCaught") // the provider documents several unchecked failures
    private fun insertPending(values: ContentValues): Uri =
        try {
            contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        } catch (e: RuntimeException) {
            throw IOException("insert failed", e)
        } ?: throw IOException("insert failed")

    private companion object {
        const val RELATIVE_PATH = "Download/Tandem/"
        const val FALLBACK_MIME = "application/octet-stream"
    }
}
