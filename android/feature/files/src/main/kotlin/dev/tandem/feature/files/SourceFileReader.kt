package dev.tandem.feature.files

import android.content.ContentResolver
import androidx.core.net.toUri
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream

/** Opens the bytes behind a user-picked [uri]; the seam keeps [FileSender] free of `ContentResolver`. */
fun interface SourceFileReader {
    @Throws(IOException::class)
    fun open(uri: String): InputStream
}

class ContentResolverSourceFileReader(
    private val contentResolver: ContentResolver,
) : SourceFileReader {
    override fun open(uri: String): InputStream =
        contentResolver.openInputStream(uri.toUri()) ?: throw FileNotFoundException()
}
