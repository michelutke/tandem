package dev.tandem.feature.files

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContract
import androidx.core.app.ActivityOptionsCompat
import androidx.core.net.toUri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

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

    @Test
    fun shareTarget_sendOneContentUri_startsOneOffer() {
        share(Intent.ACTION_SEND) { putExtra(Intent.EXTRA_STREAM, contentUri(1)) }

        assertEquals(listOf(contentUri(1).toString()), started.map { it.uri })
    }

    @Test
    fun shareTarget_sendMultipleThreeContentUris_startsThreeOffers() {
        share(Intent.ACTION_SEND_MULTIPLE) {
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList((1..3).map(::contentUri)))
        }

        assertEquals((1..3).map { contentUri(it).toString() }, started.map { it.uri })
    }

    @Test
    fun shareTarget_fileSchemeUriIntoAppDataDir_rejectedNoOffer() {
        val packageName = ApplicationProvider.getApplicationContext<android.content.Context>().packageName
        val dataFile = "file:///data/data/$packageName/files/key".toUri()

        share(Intent.ACTION_SEND) { putExtra(Intent.EXTRA_STREAM, dataFile) }

        assertTrue(started.isEmpty())
    }

    @Test
    fun shareTarget_ownFileProviderAuthorityUri_rejectedNoOffer() {
        val packageName = ApplicationProvider.getApplicationContext<android.content.Context>().packageName

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
        configure: Intent.() -> Unit,
    ) {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val intent = Intent(action).setClass(context, ShareFilesActivity::class.java).apply(configure)
        val controller = Robolectric.buildActivity(ShareFilesActivity::class.java, intent)
        controller.get().starter = TransferStarter { started += it }
        controller.create()
        assertTrue(controller.get().isFinishing)
    }

    private fun pick(result: List<Uri>) {
        val controller = Robolectric.buildActivity(PickFilesActivity::class.java)
        controller.get().starter = TransferStarter { started += it }
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
}
