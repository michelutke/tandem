package dev.tandem.feature.contacts

import android.Manifest
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Email
import android.provider.ContactsContract.CommonDataKinds.Phone
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.protocol.v1.ContactAddressType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.GraphicsMode
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

/**
 * ContentResolverContactsSource tests (E51-02), on Robolectric (E00-20) against a fake
 * ContactsContract provider registered for the real `com.android.contacts` authority.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ContentResolverContactsSourceTest {
    private val context = RuntimeEnvironment.getApplication()
    private val provider =
        Robolectric.setupContentProvider(FakeContactsProvider::class.java, ContactsContract.AUTHORITY)
    private val source = ContentResolverContactsSource(context)

    @Test
    fun contactsSource_twoPhonesOneEmail_mapsToSingleContactRecord() {
        provider.rows =
            listOf(
                FakeContactRow(
                    id = 7,
                    name = "Ada Lovelace",
                    updatedAtMs = 1234,
                    phones = listOf("+41 79 111 22 33" to Phone.TYPE_MOBILE, "044 555 66 77" to Phone.TYPE_WORK),
                    emails = listOf("ada@example.com" to Email.TYPE_HOME),
                ),
            )

        val page = source.readPage(afterContactId = 0)

        assertEquals(1, page.contacts.size)
        assertNull(page.nextAfterContactId)
        val contact = page.contacts.single()
        assertEquals("7", contact.contactId)
        assertEquals("Ada Lovelace", contact.displayName)
        assertEquals(1234L, contact.updatedAtMs)
        assertEquals(listOf("+41 79 111 22 33", "044 555 66 77"), contact.phoneNumbersList.map { it.number })
        assertEquals(
            listOf(ContactAddressType.CONTACT_ADDRESS_TYPE_MOBILE, ContactAddressType.CONTACT_ADDRESS_TYPE_WORK),
            contact.phoneNumbersList.map { it.type },
        )
        assertEquals(1, contact.emailsCount)
        assertEquals("ada@example.com", contact.getEmails(0).address)
        assertEquals(ContactAddressType.CONTACT_ADDRESS_TYPE_HOME, contact.getEmails(0).type)
    }

    @Test
    fun contactsSource_twoThousandContactFixture_tenPagesNoneOver200() {
        provider.rows = (1L..2000L).map { FakeContactRow(id = it, name = "Contact $it", updatedAtMs = it) }

        val pageSizes = mutableListOf<Int>()
        var afterContactId: Long? = 0
        while (afterContactId != null) {
            val page = source.readPage(afterContactId)
            pageSizes += page.contacts.size
            afterContactId = page.nextAfterContactId
        }

        assertEquals(List(10) { 200 }, pageSizes)
        assertFalse(provider.cursorOpenedWhilePreviousOpen)
    }

    @Test
    fun contactsSource_readContactsGranted_reportsPermission() {
        assertFalse(source.hasReadPermission())

        shadowOf(context).grantPermissions(Manifest.permission.READ_CONTACTS)

        assertTrue(source.hasReadPermission())
    }

    @Test
    fun contactsSource_sinceUpdatedAt_returnsOnlyNewerContacts() {
        provider.rows = listOf(FakeContactRow(1, "Old", 10), FakeContactRow(2, "New", 99))

        val page = source.readPage(afterContactId = 0, sinceUpdatedAtMs = 10)

        assertEquals(listOf("2"), page.contacts.map { it.contactId })
    }

    @Test
    fun contactsSource_deletedContacts_returnsIdsDeletedAfterSince() {
        provider.deletedContacts = listOf(4L to 5L, 8L to 50L, 6L to 60L)

        assertEquals(listOf("6", "8"), source.readDeletedContactIds(sinceDeletedAtMs = 10))
    }

    @Test
    fun contactsSource_contactWithPhoto_setsScaledPhotoThumbnail() {
        val photoUri = "content://com.android.contacts/contacts/1/photo_thumb"
        val bitmap = Bitmap.createBitmap(512, 384, Bitmap.Config.ARGB_8888)
        val jpeg = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()
        shadowOf(context.contentResolver).registerInputStream(Uri.parse(photoUri), ByteArrayInputStream(jpeg))
        provider.rows = listOf(FakeContactRow(id = 1, name = "Ada", updatedAtMs = 1, photoThumbnailUri = photoUri))

        val contact = source.readPage(afterContactId = 0).contacts.single()

        val thumbnail = contact.photoThumbnail.toByteArray()
        val decoded = requireNotNull(BitmapFactory.decodeByteArray(thumbnail, 0, thumbnail.size))
        assertTrue(maxOf(decoded.width, decoded.height) <= ThumbnailScaler.MAX_EDGE_PX)
    }

    @Test
    fun contactsSource_contactWithoutPhotoOrCorruptPhoto_hasNoPhotoThumbnail() {
        val corruptUri = "content://com.android.contacts/contacts/2/photo_thumb"
        shadowOf(
            context.contentResolver,
        ).registerInputStream(
            Uri.parse(corruptUri),
            ByteArrayInputStream(
                ByteArray(64) {
                    it.toByte()
                },
            ),
        )
        provider.rows =
            listOf(
                FakeContactRow(id = 1, name = "No photo", updatedAtMs = 1),
                FakeContactRow(id = 2, name = "Corrupt", updatedAtMs = 2, photoThumbnailUri = corruptUri),
            )

        val contacts = source.readPage(afterContactId = 0).contacts

        assertEquals(2, contacts.size)
        assertTrue(contacts.all { it.photoThumbnail.isEmpty })
    }
}
