package dev.tandem.feature.files

import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayInputStream
import java.io.InputStream

// E40-05 tdd (docs/planning/backlog/phase-4.yaml). Runs on the api35 managed device (E00-21).
@RunWith(AndroidJUnit4::class)
class MediaStoreDownloadsPublisherInstrumentedTest {
    private val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
    private val publisher = MediaStoreDownloadsPublisher(resolver)
    private val prefix = "tandem-e40-05-${System.nanoTime()}"

    @After
    fun cleanUp() {
        resolver.delete(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            "${MediaStore.Downloads.DISPLAY_NAME} LIKE ?",
            arrayOf("$prefix%"),
        )
    }

    @Test
    fun mediaStorePublisher_pendingPublish_invisibleToDownloadTandemQuery() {
        var visibleDuringCopy = -1
        val probe =
            object : InputStream() {
                private val delegate = ByteArrayInputStream(ByteArray(16))

                override fun read(): Int = delegate.read()

                override fun read(
                    b: ByteArray,
                    off: Int,
                    len: Int,
                ): Int {
                    visibleDuringCopy = rowsNamed("$prefix.bin").size
                    return delegate.read(b, off, len)
                }
            }

        publisher.publish("$prefix.bin", "application/octet-stream", probe)

        assertEquals(0, visibleDuringCopy)
        assertEquals(1, rowsNamed("$prefix.bin").size)
    }

    @Test
    fun mediaStorePublisher_existingSameName_originalUntouchedAndSuffixedEntryAdded() {
        val original = byteArrayOf(1, 2, 3)
        publisher.publish("$prefix.pdf", "application/pdf", ByteArrayInputStream(original))
        publisher.publish("$prefix.pdf", "application/pdf", ByteArrayInputStream(byteArrayOf(9)))

        val rows = rowsNamed("$prefix%")
        assertEquals(2, rows.size)
        val first = rows.single { it.first == "$prefix.pdf" }
        assertArrayEquals(original, resolver.openInputStream(first.second)!!.use { it.readBytes() })
    }

    private fun rowsNamed(pattern: String): List<Pair<String, android.net.Uri>> {
        val rows = mutableListOf<Pair<String, android.net.Uri>>()
        resolver
            .query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.DISPLAY_NAME),
                "${MediaStore.Downloads.DISPLAY_NAME} LIKE ? AND ${MediaStore.Downloads.RELATIVE_PATH} LIKE ?",
                arrayOf(pattern, "Download/Tandem/%"),
                null,
            )?.use {
                while (it.moveToNext()) {
                    rows +=
                        it.getString(1) to
                        android.content.ContentUris.withAppendedId(
                            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                            it.getLong(0),
                        )
                }
            }
        return rows
    }
}
