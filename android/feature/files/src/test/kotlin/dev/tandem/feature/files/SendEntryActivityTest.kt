package dev.tandem.feature.files

import android.app.Activity
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContract
import androidx.core.app.ActivityOptionsCompat
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
import org.robolectric.android.controller.ActivityController
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicInteger

// E40-11 tdd (docs/planning/backlog/phase-4.yaml):
//   unit: shareTarget_sendMultipleThreeContentUris_startsThreeOffers
//   unit: shareTarget_fileSchemeUriIntoAppDataDir_rejectedNoOffer
//   unit: shareTarget_ownFileProviderAuthorityUri_rejectedNoOffer
//   unit: shareTarget_twentyOneStreams_rejectedNoOffer
//   unit: safPicker_uriReturned_startsOneOffer
//   unit: safPicker_cancelled_noOfferStarted
//
// Robolectric (E00-20): the entry points are Activities. A recording TransferStarter stands in for
// the transfer service; the picker is driven by a test ActivityResultRegistry.
@RunWith(AndroidJUnit4::class)
class SendEntryActivityTest {
    private val started = mutableListOf<SendRequest>()
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun shareTarget_sendOneContentUri_startsOneOffer() {
        share(Intent.ACTION_SEND) { putExtra(Intent.EXTRA_STREAM, contentUri(1)) }

        assertEquals(1, started.size)
    }

    @Test
    fun shareTarget_sendMultipleThreeContentUris_startsThreeOffers() {
        share(Intent.ACTION_SEND_MULTIPLE) {
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList((1..3).map(::contentUri)))
        }

        assertEquals(3, started.size)
    }

    @Test
    fun shareTarget_fileSchemeUriIntoAppDataDir_rejectedNoOffer() {
        val packageName = context.packageName
        val dataFile = "file:///data/data/$packageName/files/key".toUri()

        share(Intent.ACTION_SEND) { putExtra(Intent.EXTRA_STREAM, dataFile) }

        assertTrue(started.isEmpty())
    }

    @Test
    fun shareTarget_ownFileProviderAuthorityUri_rejectedNoOffer() {
        val packageName = context.packageName

        share(Intent.ACTION_SEND) { putExtra(Intent.EXTRA_STREAM, "content://$packageName.fileprovider/f/1".toUri()) }

        assertTrue(started.isEmpty())
    }

    @Test
    fun shareTarget_twentyOneStreams_rejectedNoOffer() {
        share(Intent.ACTION_SEND_MULTIPLE) {
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList((1..21).map(::contentUri)))
        }

        assertTrue(started.isEmpty())
    }

    @Test
    fun shareTarget_twentyStreams_startsTwentyOffers() {
        share(Intent.ACTION_SEND_MULTIPLE) {
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList((1..20).map(::contentUri)))
        }

        assertEquals(20, started.size)
    }

    @Test
    fun shareFilesActivity_streamOpenableOnlyOnce_transferSourceStillReadsTwice() {
        val uri = contentUri(1)
        shadowOf(context.contentResolver).registerInputStream(uri, ByteArrayInputStream("payload".toByteArray()))

        share(Intent.ACTION_SEND, registerStreams = false) { putExtra(Intent.EXTRA_STREAM, uri) }

        val reader = ContentResolverSourceFileReader(context.contentResolver)
        val request = started.single()
        assertEquals(
            listOf("payload", "payload"),
            List(2) { reader.open(request.uri).use { it.readBytes().decodeToString() } },
        )
        assertTrue(
            File(
                request.uri
                    .toUri()
                    .path
                    .orEmpty(),
            ).startsWith(context.cacheDir),
        )
    }

    @Test
    fun shareFilesActivity_requestFinished_stagedCopyDeleted() {
        share(Intent.ACTION_SEND) { putExtra(Intent.EXTRA_STREAM, contentUri(1)) }
        val staged =
            File(
                started
                    .single()
                    .uri
                    .toUri()
                    .path
                    .orEmpty(),
            )
        assertTrue(staged.exists())

        ShareStaging(File(context.cacheDir, ShareStaging.DIRECTORY_NAME)).delete(started.single())

        assertFalse(staged.exists())
    }

    @Test
    fun shareFilesActivity_sourceUnreadable_noOfferAndFailureReported() {
        val failures = AtomicInteger()
        shadowOf(context.contentResolver).registerInputStream(
            contentUri(1),
            object : InputStream() {
                override fun read(): Int = throw IOException("unreadable")
            },
        )

        share(Intent.ACTION_SEND, registerStreams = false, onStagingFailed = { failures.incrementAndGet() }) {
            putExtra(Intent.EXTRA_STREAM, contentUri(1))
        }

        assertTrue(started.isEmpty())
        assertEquals(1, failures.get())
    }

    @Test
    fun shareFilesActivity_offerQueuedOnExecutor_nothingReadOnCallerAndFinishesAfterwards() {
        val queued = mutableListOf<Runnable>()
        val controller =
            buildShare(Intent.ACTION_SEND, registerStreams = true, executor = { queued += it }) {
                putExtra(Intent.EXTRA_STREAM, contentUri(1))
            }

        assertTrue(started.isEmpty())
        assertFalse(controller.get().isFinishing)

        queued.forEach(Runnable::run)

        assertEquals(1, started.size)
        assertTrue(controller.get().isFinishing)
    }

    @Test
    fun shareFilesActivity_recreatedWithSavedState_doesNotStageAgain() {
        val queued = mutableListOf<Runnable>()
        val intent =
            Intent(Intent.ACTION_SEND).setClass(context, ShareFilesActivity::class.java).apply {
                putExtra(Intent.EXTRA_STREAM, contentUri(1))
            }
        registerContent(contentUri(1))
        val controller = Robolectric.buildActivity(ShareFilesActivity::class.java, intent)
        controller.get().starter = TransferStarter { started += it }
        controller.get().executor = { queued += it }

        controller.create(Bundle())

        assertTrue(queued.isEmpty())
        assertTrue(started.isEmpty())
    }

    @Test
    fun shareFilesActivity_providerThrowsSecurityException_failureReportedNoCrash() {
        Robolectric.buildContentProvider(SecurityThrowingProvider::class.java).create(THROWING_AUTHORITY)
        val failures = AtomicInteger()

        share(Intent.ACTION_SEND, registerStreams = false, onStagingFailed = { failures.incrementAndGet() }) {
            putExtra(Intent.EXTRA_STREAM, "content://$THROWING_AUTHORITY/doc/1".toUri())
        }

        assertTrue(started.isEmpty())
        assertEquals(1, failures.get())
    }

    @Test
    fun shareFilesActivity_streamThrowsSecurityExceptionMidCopy_failureReportedAndPartialDeleted() {
        val failures = AtomicInteger()
        shadowOf(context.contentResolver).registerInputStream(
            contentUri(1),
            object : InputStream() {
                override fun read(): Int = throw SecurityException("revoked")
            },
        )

        share(Intent.ACTION_SEND, registerStreams = false, onStagingFailed = { failures.incrementAndGet() }) {
            putExtra(Intent.EXTRA_STREAM, contentUri(1))
        }

        assertTrue(started.isEmpty())
        assertEquals(1, failures.get())
        assertTrue(File(context.cacheDir, ShareStaging.DIRECTORY_NAME).listFiles().orEmpty().isEmpty())
    }

    @Test
    fun safPicker_uriReturned_startsOneOffer() {
        pick(listOf(contentUri(7)))

        assertEquals(listOf(contentUri(7).toString()), started.map { it.uri })
    }

    @Test
    fun safPicker_cancelled_noOfferStarted() {
        pick(emptyList())

        assertTrue(started.isEmpty())
    }

    private fun share(
        action: String,
        registerStreams: Boolean = true,
        onStagingFailed: () -> Unit = {},
        configure: Intent.() -> Unit,
    ) {
        val controller =
            buildShare(action, registerStreams, executor = { it.run() }, onStagingFailed = onStagingFailed, configure)
        assertTrue(controller.get().isFinishing)
    }

    private fun buildShare(
        action: String,
        registerStreams: Boolean,
        executor: Executor,
        onStagingFailed: () -> Unit = {},
        configure: Intent.() -> Unit,
    ): ActivityController<ShareFilesActivity> {
        val intent = Intent(action).setClass(context, ShareFilesActivity::class.java).apply(configure)
        if (registerStreams) streamsOf(intent).forEach { registerContent(it) }
        val controller = Robolectric.buildActivity(ShareFilesActivity::class.java, intent)
        controller.get().starter = TransferStarter { started += it }
        controller.get().executor = executor
        controller.get().onStagingFailed = onStagingFailed
        controller.create()
        return controller
    }

    private fun streamsOf(intent: Intent): List<Uri> =
        listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)) +
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()

    private fun registerContent(uri: Uri) {
        if (uri.scheme ==
            "content"
        ) {
            shadowOf(context.contentResolver).registerInputStream(uri, ByteArrayInputStream(ByteArray(8)))
        }
    }

    private fun pick(result: List<Uri>) {
        val controller = Robolectric.buildActivity(PickFilesActivity::class.java)
        controller.get().starter = TransferStarter { started += it }
        controller.get().executor = Executor { it.run() }
        controller.get().registry =
            object : ActivityResultRegistry() {
                override fun <I, O> onLaunch(
                    requestCode: Int,
                    contract: ActivityResultContract<I, O>,
                    input: I,
                    options: ActivityOptionsCompat?,
                ) {
                    dispatchResult(requestCode, result)
                }
            }
        controller.create().start().resume()
        assertTrue(controller.get().isFinishing)
    }

    private fun contentUri(index: Int): Uri = "content://com.android.providers.media.documents/document/$index".toUri()

    private companion object {
        const val THROWING_AUTHORITY = "throwing.provider"
    }
}

class SecurityThrowingProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = throw SecurityException("not granted")

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor = throw SecurityException("not granted")

    override fun insert(
        uri: Uri,
        values: ContentValues?,
    ): Uri? = null

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
