package dev.tandem.feature.files

import android.content.Intent
import android.os.Bundle
import androidx.core.net.toUri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class ShareFilesActivityRecreationTest {
    private val started = mutableListOf<SendRequest>()
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val uri = "content://com.android.providers.media.documents/document/1".toUri()

    private fun intent(): Intent =
        Intent(Intent.ACTION_SEND).setClass(context, ShareFilesActivity::class.java).apply {
            putExtra(Intent.EXTRA_STREAM, uri)
        }

    @Test
    fun shareFilesActivity_recreatedWhileStagingRuns_recreatedInstanceFinishesWhenStagingEnds() {
        val queued = mutableListOf<Runnable>()
        shadowOf(context.contentResolver).registerInputStream(uri, ByteArrayInputStream(ByteArray(8)))
        val controller = Robolectric.buildActivity(ShareFilesActivity::class.java, intent())
        controller.get().starter = TransferStarter { started += it }
        controller.get().executor = { queued += it }
        controller.create().start().resume()

        controller.recreate()

        assertFalse(controller.get().isFinishing)
        queued.forEach(Runnable::run)
        assertEquals(1, started.size)
        assertTrue(controller.get().isFinishing)
    }

    @Test
    fun shareFilesActivity_recreatedAfterStagingEnded_finishesAtOnce() {
        shadowOf(context.contentResolver).registerInputStream(uri, ByteArrayInputStream(ByteArray(8)))
        val controller = Robolectric.buildActivity(ShareFilesActivity::class.java, intent())
        controller.get().starter = TransferStarter { started += it }
        controller.get().executor = { it.run() }
        controller.create().start().resume()

        controller.recreate()

        assertEquals(1, started.size)
        assertTrue(controller.get().isFinishing)
    }

    @Test
    fun shareFilesActivity_savedStateWithoutRunningJob_finishesAtOnceWithFailedFeedback() {
        val failures = AtomicInteger()
        val controller = Robolectric.buildActivity(ShareFilesActivity::class.java, intent())
        controller.get().starter = TransferStarter { started += it }
        controller.get().executor = { it.run() }
        controller.get().onStagingFailed = { failures.incrementAndGet() }

        controller.create(Bundle())

        assertTrue(started.isEmpty())
        assertEquals(1, failures.get())
        assertTrue(controller.get().isFinishing)
    }
}
