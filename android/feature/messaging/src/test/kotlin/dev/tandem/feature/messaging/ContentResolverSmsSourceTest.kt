package dev.tandem.feature.messaging

import android.Manifest
import android.os.Looper
import android.provider.Telephony
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.cash.turbine.test
import dev.tandem.protocol.v1.SmsMessageType
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/**
 * ContentResolverSmsSource tests (E50-02), on Robolectric (E00-20) against a fake provider
 * registered for the real `sms` and `mms-sms` authorities.
 */
@RunWith(AndroidJUnit4::class)
class ContentResolverSmsSourceTest {
    private val context = RuntimeEnvironment.getApplication()
    private val smsProvider = Robolectric.setupContentProvider(FakeSmsProvider::class.java, "sms")
    private val conversationsProvider = Robolectric.setupContentProvider(FakeSmsProvider::class.java, "mms-sms")
    private val source = ContentResolverSmsSource(context)

    init {
        shadowOf(context).grantPermissions(Manifest.permission.READ_SMS)
    }

    @Test
    fun smsSource_olderThanOnFiveThousandRows_returnsDescending200IdWindow() {
        smsProvider.smsRows = (1L..5000L).map { FakeSmsRow(it) }

        val page = source.olderThan(5001, 200)

        assertEquals((5000L downTo 4801L).toList(), page.map { it.id })
    }

    @Test
    fun smsSource_newerThanWatermark_returnsAscendingRowsAboveWatermarkOnly() {
        smsProvider.smsRows = (1L..5000L).map { FakeSmsRow(it) }

        val page = source.newerThan(4990, 200)

        assertEquals((4991L..5000L).toList(), page.map { it.id })
    }

    @Test
    fun smsSource_fullFiveThousandRowWalk_noCallExceedsPageSizeAndCursorsClosed() {
        smsProvider.smsRows = (1L..5000L).map { FakeSmsRow(it) }

        val walked = mutableListOf<Long>()
        var beforeId = 5001L
        while (true) {
            val page = source.olderThan(beforeId, SmsSource.PAGE_SIZE)
            if (page.isEmpty()) break
            walked += page.map { it.id }
            beforeId = page.last().id
        }

        assertEquals(5000, walked.size)
        assertTrue(smsProvider.returnedRowCounts.all { it <= SmsSource.PAGE_SIZE })
        assertFalse(smsProvider.cursorOpenedWhilePreviousOpen)
    }

    @Test
    fun smsSource_mmsRowsInProvider_excludedFromResults() {
        smsProvider.smsRows = listOf(FakeSmsRow(1), FakeSmsRow(3))
        smsProvider.mmsRows = listOf(FakeSmsRow(2))

        assertEquals(listOf(1L, 3L), source.newerThan(0, 200).map { it.id })
        assertEquals(listOf(3L, 1L), source.olderThan(10, 200).map { it.id })
    }

    @Test
    fun smsSource_rowFields_mapToSmsMessage() {
        smsProvider.smsRows =
            listOf(FakeSmsRow(5, threadId = 9, address = "5559999", body = "hi", dateMs = 42, type = 2, subId = 3))

        val message = source.newerThan(0, 10).single()

        assertEquals(9L, message.threadId)
        assertEquals("5559999", message.address)
        assertEquals("hi", message.body)
        assertEquals(42L, message.timestampMs)
        assertEquals(SmsMessageType.SMS_MESSAGE_TYPE_SENT, message.type)
        assertEquals(3, message.subscriptionId)
    }

    @Test
    fun smsSource_maxId_returnsHighestIdOrZero() {
        assertEquals(0L, source.maxId())

        smsProvider.smsRows = listOf(FakeSmsRow(4), FakeSmsRow(9), FakeSmsRow(6))

        assertEquals(9L, source.maxId())
    }

    @Test
    fun smsSource_threads_mapsConversationRowsNewestFirst() {
        conversationsProvider.conversations =
            listOf(
                FakeConversationRow(1, "5551111", "old", 10),
                FakeConversationRow(2, "5552222", "new", 20),
            )

        val threads = source.threads()

        assertEquals(listOf(2L, 1L), threads.map { it.threadId })
        assertEquals("5552222", threads.first().address)
        assertEquals("new", threads.first().snippet)
        assertEquals(20L, threads.first().lastMessageAtMs)
    }

    @Test
    fun smsSource_threadsWithUnreadRows_countsUnreadPerThread() {
        conversationsProvider.conversations =
            listOf(FakeConversationRow(1, "5551111", "a", 10), FakeConversationRow(2, "5552222", "b", 20))
        smsProvider.smsRows =
            listOf(
                FakeSmsRow(1, threadId = 1, read = false),
                FakeSmsRow(2, threadId = 1, read = false),
                FakeSmsRow(3, threadId = 1),
                FakeSmsRow(4, threadId = 2),
            )

        assertEquals(mapOf(1L to 2, 2L to 0), source.threads().associate { it.threadId to it.unreadCount })
    }

    @Test
    fun smsSource_readSmsNotGranted_throwsSmsPermissionMissing() {
        shadowOf(context).denyPermissions(Manifest.permission.READ_SMS)

        assertThrows(SmsPermissionMissing::class.java) { source.threads() }
        assertThrows(SmsPermissionMissing::class.java) { source.newerThan(0, 10) }
        assertThrows(SmsPermissionMissing::class.java) { source.olderThan(10, 10) }
        assertThrows(SmsPermissionMissing::class.java) { source.maxId() }
    }

    @Test
    fun smsSource_providerThrowsSecurityException_throwsSmsPermissionMissing() {
        smsProvider.failWithSecurityException = true

        assertThrows(SmsPermissionMissing::class.java) { source.maxId() }
    }

    @Test
    fun contentResolverSmsSource_providerNotifyChange_emitsOnChangesFlow() =
        runTest {
            source.changes().test {
                context.contentResolver.notifyChange(Telephony.Sms.CONTENT_URI, null)
                shadowOf(Looper.getMainLooper()).idle()

                awaitItem()
                expectNoEvents()
                cancelAndIgnoreRemainingEvents()
            }
        }
}
