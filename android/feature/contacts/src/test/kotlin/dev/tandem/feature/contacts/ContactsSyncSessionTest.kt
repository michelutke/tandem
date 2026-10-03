package dev.tandem.feature.contacts

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Contact
import dev.tandem.protocol.v1.ContactsSyncStatus
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.contact
import dev.tandem.protocol.v1.contactsSyncRequest
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** ContactsSyncSession tests (E51-02; `docs/planning/backlog/phase-5.yaml` E51-02's `tdd:` list). */
@OptIn(ExperimentalCoroutinesApi::class)
class ContactsSyncSessionTest {
    @Test
    fun contactsSyncSession_zeroChannelCredits_sendsNoFurtherPage() =
        runTest {
            val inner = FakeTandemSession()
            val credits = Semaphore(permits = 2, acquiredPermits = 2)
            val source = FakeContactsSource(contacts(5), pageSize = 2)
            val sync = syncSession(source, CreditGatedSession(inner, credits))

            val job = launch { sync.handle(request(0)) }
            runCurrent()
            assertEquals(0, inner.sentFrames.size)

            credits.release()
            runCurrent()
            assertEquals(1, inner.sentFrames.size)
            assertTrue(job.isActive)

            credits.release()
            runCurrent()
            assertEquals(2, inner.sentFrames.size)
            credits.release()
            runCurrent()
            assertEquals(
                listOf(false, false, true),
                inner.sentFrames.map { it.contactsSyncResponse.complete },
            )
            assertEquals(ContactsSyncStatus.CONTACTS_SYNC_STATUS_OK, inner.sentFrames[0].contactsSyncResponse.status)
            assertEquals(
                5L,
                inner.sentFrames
                    .last()
                    .contactsSyncResponse.watermarkMs,
            )
        }

    @Test
    fun contactsSyncSession_readContactsNotGranted_respondsPermissionRequired() =
        runTest {
            val inner = FakeTandemSession()
            val source = FakeContactsSource(contacts(3), readPermitted = false)

            syncSession(source, inner).handle(request(0))

            assertEquals(1, inner.sentFrames.size)
            val frame = inner.sentFrames.single()
            assertEquals(Channel.CHANNEL_CONTACTS, frame.channel)
            assertEquals(
                ContactsSyncStatus.CONTACTS_SYNC_STATUS_PERMISSION_REQUIRED,
                frame.contactsSyncResponse.status,
            )
            assertEquals(0, frame.contactsSyncResponse.contactsCount)
            assertEquals(0, source.pagesRead)
        }

    @Test
    fun contactsSyncSession_incomingRequestOnChannel_streamsPages() =
        runTest {
            val inner = FakeTandemSession()
            val source = FakeContactsSource(contacts(3), pageSize = 2)
            val sync = syncSession(source, inner)
            val job = launch { sync.run() }
            runCurrent()

            inner.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CONTACTS
                    contactsSyncRequest = request(0)
                },
            )
            runCurrent()

            assertEquals(listOf(2, 1), inner.sentFrames.map { it.contactsSyncResponse.contactsCount })
            job.cancel()
        }

    @Test
    fun contactsSyncSession_sinceWatermark_sendsOnlyNewerContacts() =
        runTest {
            val inner = FakeTandemSession()
            val sync = syncSession(FakeContactsSource(contacts(4)), inner)

            sync.handle(request(sinceUpdatedAtMs = 2))

            val sent = inner.sentFrames.single().contactsSyncResponse
            assertEquals(listOf("3", "4"), sent.contactsList.map { it.contactId })
            assertEquals(4L, sent.watermarkMs)
            assertTrue(sent.complete)
        }

    private fun TestScope.syncSession(
        source: ContactsSource,
        session: TandemSession,
    ) = ContactsSyncSession(source, session, StandardTestDispatcher(testScheduler))

    private fun request(sinceUpdatedAtMs: Long) = contactsSyncRequest { this.sinceUpdatedAtMs = sinceUpdatedAtMs }

    private fun contacts(count: Int): List<Contact> =
        (1..count).map {
            contact {
                contactId = it.toString()
                displayName = "Contact $it"
                updatedAtMs = it.toLong()
            }
        }

    private class CreditGatedSession(
        private val inner: FakeTandemSession,
        private val credits: Semaphore,
    ) : TandemSession by inner {
        override suspend fun send(
            channel: Channel,
            payload: EnvelopeKt.Dsl.() -> Unit,
        ) {
            credits.acquire()
            inner.send(channel, payload)
        }
    }
}
