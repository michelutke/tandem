package dev.tandem.feature.files

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream

/** The device ran out of space while writing a transfer; the receiver answers `INSUFFICIENT_SPACE`. */
class InsufficientSpaceException(
    cause: Throwable? = null,
) : IOException("no space left on device", cause)

/** App-private staging area for in-flight `<id>.part` files (E40-05). */
interface TransferStore {
    @Throws(IOException::class)
    fun create(id: String)

    @Throws(IOException::class)
    fun append(
        id: String,
        data: ByteArray,
    )

    @Throws(IOException::class)
    fun open(id: String): InputStream

    fun delete(id: String)

    fun deleteAll()
}

/** [TransferStore] over `<directory>/<id>.part`; [directory] is the app's `noBackupFilesDir` subfolder. */
class FileTransferStore(
    private val directory: File,
) : TransferStore {
    override fun create(id: String) {
        directory.mkdirs()
        file(id).delete()
        if (!file(id).createNewFile()) throw IOException("part file exists")
    }

    override fun append(
        id: String,
        data: ByteArray,
    ) {
        try {
            FileOutputStream(file(id), true).use { it.write(data) }
        } catch (e: IOException) {
            if (e.message?.contains(NO_SPACE_MESSAGE, ignoreCase = true) == true) throw InsufficientSpaceException(e)
            throw e
        }
    }

    override fun open(id: String): InputStream = file(id).inputStream()

    override fun delete(id: String) {
        file(id).delete()
    }

    override fun deleteAll() {
        directory.listFiles { candidate -> candidate.name.endsWith(PART_SUFFIX) }?.forEach { it.delete() }
    }

    private fun file(id: String): File =
        File(directory, "${id.filter { it.isLetterOrDigit() || it == '-' }}$PART_SUFFIX")

    private companion object {
        const val PART_SUFFIX = ".part"
        const val NO_SPACE_MESSAGE = "No space left"
    }
}
