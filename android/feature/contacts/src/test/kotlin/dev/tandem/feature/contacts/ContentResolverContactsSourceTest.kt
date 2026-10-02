package dev.tandem.feature.contacts

import android.Manifest
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

/**
 * ContentResolverContactsSource tests (E51-02), on Robolectric (E00-20) against a fake
 * ContactsContract provider registered for the real `com.android.contacts` authority.
 */
@RunWith(AndroidJUnit4::class)
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
}
