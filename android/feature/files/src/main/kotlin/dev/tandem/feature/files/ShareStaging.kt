package dev.tandem.feature.files

import android.content.ContentResolver
import android.net.Uri
import androidx.core.net.toUri
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/**
 * App-cache copies of files shared from other apps (E40-11). A share-sheet read grant ends with the
 * receiving activity, but [FileSender] reopens the stream only after the Mac accepts, so each stream
 * is copied here, bounded by a byte limit, while the grant is alive. The copy is deleted when its
 * transfer ends ([delete]) and any leftovers when the app next starts ([sweep]).
 */
class ShareStaging(
    private val directory: File,
) {
    @Throws(IOException::class)
    fun stage(
        contentResolver: ContentResolver,
        uri: Uri,
        id: String,
        limit: Long,
    ): File {
        directory.mkdirs()
        val target = File(directory, id)
        var complete = false
        try {
            val input = openSource(contentResolver, uri)
            input.use { source -> target.outputStream().use { copyBounded(source, it, limit) } }
            complete = true
        } finally {
            if (!complete) target.delete()
        }
        return target
    }

    fun delete(request: SendRequest) {
        val file =
            request.uri
                .toUri()
                .path
                ?.let(::File) ?: return
        if (file.parentFile?.canonicalFile == directory.canonicalFile) file.delete()
    }

    fun sweep() {
        directory.listFiles()?.forEach { it.delete() }
    }

    private fun openSource(
        contentResolver: ContentResolver,
        uri: Uri,
    ): InputStream =
        try {
            contentResolver.openInputStream(uri) ?: throw FileNotFoundException()
        } catch (_: SecurityException) {
            throw FileNotFoundException()
        }

    private fun copyBounded(
        source: InputStream,
        sink: OutputStream,
        limit: Long,
    ) {
        val buffer = ByteArray(BUFFER_BYTES)
        var total = 0L
        while (true) {
            val read = source.read(buffer)
            if (read < 0) return
            total += read
            if (total > limit) throw IOException("shared file over the staging limit")
            sink.write(buffer, 0, read)
        }
    }

    companion object {
        const val DIRECTORY_NAME = "share-staging"

        /** Bytes one share may stage in total; a share over it fails visibly instead of filling the cache. */
        const val MAX_STAGED_BYTES = 512L * 1024 * 1024

        private const val BUFFER_BYTES = 64 * 1024

        fun inCache(cacheDir: File): ShareStaging = ShareStaging(File(cacheDir, DIRECTORY_NAME))
    }
}
