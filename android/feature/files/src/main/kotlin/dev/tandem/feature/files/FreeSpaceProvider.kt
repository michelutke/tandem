package dev.tandem.feature.files

import android.os.StatFs
import java.io.File

/** Free bytes available for incoming files (E40-07). */
fun interface FreeSpaceProvider {
    fun freeBytes(): Long
}

/** [FreeSpaceProvider] over [StatFs] for the volume holding [directory]. */
class StatFsFreeSpaceProvider(
    private val directory: File,
) : FreeSpaceProvider {
    override fun freeBytes(): Long = StatFs(directory.path).availableBytes
}
