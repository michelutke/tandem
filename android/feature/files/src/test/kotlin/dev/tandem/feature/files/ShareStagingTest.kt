package dev.tandem.feature.files

import androidx.core.net.toUri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream

@RunWith(AndroidJUnit4::class)
class ShareStagingTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val resolver = ApplicationProvider.getApplicationContext<android.content.Context>().contentResolver
    private val uri = "content://com.example.provider/doc/1".toUri()

    private fun staging() = ShareStaging(File(folder.root, "staging"))

    private fun serve(bytes: ByteArray) = shadowOf(resolver).registerInputStream(uri, ByteArrayInputStream(bytes))

    @Test
    fun shareStaging_stage_copiesBytesIntoStagingDirectory() {
        serve("payload".toByteArray())

        val staged = staging().stage(resolver, uri, "id-1", limit = 100)

        assertArrayEquals("payload".toByteArray(), staged.readBytes())
        assertEquals(File(folder.root, "staging"), staged.parentFile)
    }

    @Test
    fun shareStaging_sourceOverLimit_throwsAndLeavesNoFile() {
        serve(ByteArray(11))

        assertThrows(IOException::class.java) { staging().stage(resolver, uri, "id-1", limit = 10) }

        assertFalse(File(folder.root, "staging/id-1").exists())
    }

    @Test
    fun shareStaging_sourceExactlyAtLimit_staged() {
        serve(ByteArray(10))

        val staged = staging().stage(resolver, uri, "id-1", limit = 10)

        assertEquals(10L, staged.length())
    }

    @Test
    fun shareStaging_unreadableSource_throwsIoException() {
        shadowOf(resolver).registerInputStream(
            uri,
            object : InputStream() {
                override fun read(): Int = throw IOException("unreadable")
            },
        )

        assertThrows(IOException::class.java) { staging().stage(resolver, uri, "id-1", limit = 10) }
    }

    @Test
    fun shareStaging_deleteStagedRequest_removesFile() {
        serve(ByteArray(3))
        val staging = staging()
        val staged = staging.stage(resolver, uri, "id-1", limit = 10)

        staging.delete(SendRequest("id-1", staged.toUri().toString(), "name", "text/plain"))

        assertFalse(staged.exists())
    }

    @Test
    fun shareStaging_deleteRequestOutsideStagingDirectory_keepsFile() {
        val outside = folder.newFile("keep")

        staging().delete(SendRequest("id-1", outside.toUri().toString(), "name", "text/plain"))

        assertTrue(outside.exists())
    }

    @Test
    fun shareStaging_sweep_removesEveryStagedFile() {
        serve(ByteArray(3))
        val staging = staging()
        val staged = staging.stage(resolver, uri, "id-1", limit = 10)

        staging.sweep()

        assertFalse(staged.exists())
    }
}
