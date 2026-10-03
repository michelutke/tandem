package dev.tandem.feature.files

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.time.Clock

/** The device ran out of space while writing a transfer; the receiver answers `INSUFFICIENT_SPACE`. */
class InsufficientSpaceException(
    cause: Throwable? = null,
) : IOException("no space left on device", cause)

/** App-private staging area for in-flight `<id>.part` files (E40-05). */
@Suppress("TooManyFunctions") // one on-disk store operation per method
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

    /** Ids (as named on disk) of every retained `.part` file. */
    fun ids(): List<String>

    fun length(id: String): Long

    @Throws(IOException::class)
    fun truncate(
        id: String,
        length: Long,
    )

    /** Epoch millis of the last write to [id], stamped from the injected clock. */
    fun lastWriteMillis(id: String): Long

    @Throws(IOException::class)
    fun writeMeta(
        id: String,
        bytes: ByteArray,
    )

    fun readMeta(id: String): ByteArray?

    /** Removes the `.part` file and its metadata. */
    fun delete(id: String)

    fun deleteAll()
}

/** [TransferStore] over `<directory>/<id>.part`; [directory] is the app's `noBackupFilesDir` subfolder. */
@Suppress("TooManyFunctions") // implements every TransferStore operation
class FileTransferStore(
    private val directory: File,
    private val clock: Clock,
) : TransferStore {
    override fun create(id: String) {
        directory.mkdirs()
        file(id).delete()
        if (!file(id).createNewFile()) throw IOException("part file exists")
        stamp(id)
    }

    override fun append(
        id: String,
        data: ByteArray,
    ) {
        try {
            FileOutputStream(file(id), true).use { it.write(data) }
            stamp(id)
        } catch (e: IOException) {
            if (e.message?.contains(NO_SPACE_MESSAGE, ignoreCase = true) == true) throw InsufficientSpaceException(e)
            throw e
        }
    }

    override fun open(id: String): InputStream = file(id).inputStream()

    override fun ids(): List<String> =
        directory
            .listFiles { candidate -> candidate.name.endsWith(PART_SUFFIX) }
            .orEmpty()
            .map { it.name.removeSuffix(PART_SUFFIX) }

    override fun length(id: String): Long = file(id).length()

    override fun truncate(
        id: String,
        length: Long,
    ) {
        RandomAccessFile(file(id), "rw").use { it.setLength(length) }
        stamp(id)
    }

    override fun lastWriteMillis(id: String): Long = file(id).lastModified()

    override fun writeMeta(
        id: String,
        bytes: ByteArray,
    ) {
        meta(id).writeBytes(bytes)
    }

    override fun readMeta(id: String): ByteArray? = meta(id).takeIf { it.isFile }?.readBytes()

    override fun delete(id: String) {
        file(id).delete()
        meta(id).delete()
    }

    override fun deleteAll() {
        directory
            .listFiles { candidate -> candidate.name.endsWith(PART_SUFFIX) || candidate.name.endsWith(META_SUFFIX) }
            ?.forEach { it.delete() }
    }

    private fun stamp(id: String) {
        file(id).setLastModified(clock.millis())
    }

    private fun file(id: String): File = File(directory, "${safe(id)}$PART_SUFFIX")

    private fun meta(id: String): File = File(directory, "${safe(id)}$META_SUFFIX")

    private fun safe(id: String): String = id.filter { it.isLetterOrDigit() || it == '-' }

    private companion object {
        const val PART_SUFFIX = ".part"
        const val META_SUFFIX = ".meta"
        const val NO_SPACE_MESSAGE = "No space left"
    }
}
