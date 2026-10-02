package dev.tandem.feature.contacts

import android.Manifest
import android.content.ContentProviderOperation
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Email
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.CommonDataKinds.StructuredName
import android.provider.ContactsContract.RawContacts
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.Contact
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

// E51-02 tdd: instrumented: contactsSource_emulatorInsertedContacts_readBackWithPhonesAndEmails
@RunWith(AndroidJUnit4::class)
class ContentResolverContactsSourceInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Before
    fun grantContactsPermissions() {
        listOf(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS).forEach {
            instrumentation.uiAutomation.grantRuntimePermission(context.packageName, it)
        }
    }

    @Test
    fun contactsSource_emulatorInsertedContacts_readBackWithPhonesAndEmails() {
        val names = listOf("Tandem Test Ada", "Tandem Test Grace", "Tandem Test Linus")
        names.forEachIndexed { index, name -> insertContact(name, "+4179000000$index", "test$index@example.com") }

        val contacts = readAll().filter { it.displayName in names }

        assertEquals(names.sorted(), contacts.map { it.displayName }.sorted())
        contacts.forEach { contact ->
            val index = names.indexOf(contact.displayName)
            assertEquals(
                listOf("+4179000000$index"),
                contact.phoneNumbersList.map {
                    it.number.filter { c ->
                        c != ' '
                    }
                },
            )
            assertEquals(listOf("test$index@example.com"), contact.emailsList.map { it.address })
        }
    }

    private fun readAll(): List<Contact> {
        val source = ContentResolverContactsSource(context)
        val contacts = mutableListOf<Contact>()
        var afterContactId: Long? = 0
        while (afterContactId != null) {
            val page = source.readPage(afterContactId)
            contacts += page.contacts
            afterContactId = page.nextAfterContactId
        }
        return contacts
    }

    private fun insertContact(
        name: String,
        phone: String,
        email: String,
    ) {
        val operations =
            arrayListOf(
                ContentProviderOperation
                    .newInsert(RawContacts.CONTENT_URI)
                    .withValue(RawContacts.ACCOUNT_TYPE, null)
                    .withValue(RawContacts.ACCOUNT_NAME, null)
                    .build(),
                dataInsert(StructuredName.CONTENT_ITEM_TYPE)
                    .withValue(StructuredName.DISPLAY_NAME, name)
                    .build(),
                dataInsert(Phone.CONTENT_ITEM_TYPE)
                    .withValue(Phone.NUMBER, phone)
                    .withValue(Phone.TYPE, Phone.TYPE_MOBILE)
                    .build(),
                dataInsert(Email.CONTENT_ITEM_TYPE)
                    .withValue(Email.ADDRESS, email)
                    .withValue(Email.TYPE, Email.TYPE_HOME)
                    .build(),
            )
        context.contentResolver.applyBatch(ContactsContract.AUTHORITY, operations)
    }

    private fun dataInsert(mimeType: String): ContentProviderOperation.Builder =
        ContentProviderOperation
            .newInsert(ContactsContract.Data.CONTENT_URI)
            .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
            .withValue(ContactsContract.Data.MIMETYPE, mimeType)
}
