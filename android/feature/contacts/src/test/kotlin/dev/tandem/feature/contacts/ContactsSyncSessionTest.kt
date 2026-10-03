package dev.tandem.feature.contacts

import dev.tandem.core.testing.TestClock
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
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

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

    @Test
    fun contactsIncrementalSync_editedContact_pushesSingleUpdatedRecord() =
        runTest {
            val inner = FakeTandemSession()
            val source = FakeContactsSource(contacts(2) + contact(id = 3, updatedAtMs = 50))
            val sync = syncSession(source, inner)

            sync.handle(request(sinceUpdatedAtMs = 10))

            val sent = inner.sentFrames.single().contactsSyncResponse
            assertEquals(listOf("3"), sent.contactsList.map { it.contactId })
            assertEquals(50L, sent.watermarkMs)
        }

    @Test
    fun contactsIncrementalSync_deletedContact_idInDeletedContactIds() =
        runTest {
            val inner = FakeTandemSession()
            val source = FakeContactsSource(contacts(2), deletedContactIds = listOf("9"))

            syncSession(source, inner).handle(request(sinceUpdatedAtMs = 1))

            assertEquals(
                listOf("9"),
                inner.sentFrames
                    .single()
                    .contactsSyncResponse.deletedContactIdsList,
            )
        }

    @Test
    fun contactsIncrementalSync_sinceOlderThanRetention_respondsFullResyncRequired() =
        runTest {
            val inner = FakeTandemSession()
            val source = FakeContactsSource(contacts(2))
            val thirtyOneDaysMs = 31L * 24 * 60 * 60 * 1000
            val sync = syncSession(source, inner, clockEpoch = Instant.ofEpochMilli(thirtyOneDaysMs + 1))

            sync.handle(request(sinceUpdatedAtMs = 1))

            val sent = inner.sentFrames.single().contactsSyncResponse
            assertEquals(ContactsSyncStatus.CONTACTS_SYNC_STATUS_FULL_RESYNC_REQUIRED, sent.status)
            assertTrue(sent.complete)
            assertEquals(0, source.pagesRead)
        }

    @Test
    fun contactsIncrementalSync_fiftyCallbacksWithin1s_singleQuery() =
        runTest {
            val inner = FakeTandemSession()
            val source = FakeContactsSource(contacts(2))
            val sync = syncSession(source, inner)
            sync.handle(request(0))
            val readsAfterInitialSync = source.pagesRead
            val job = launch { sync.observeChanges() }
            runCurrent()

            repeat(50) {
                source.changeEvents.emit(Unit)
                advanceTimeBy(10)
            }
            advanceTimeBy(1_000)
            runCurrent()

            assertEquals(readsAfterInitialSync + 1, source.pagesRead)
            job.cancel()
        }

    private fun TestScope.syncSession(
        source: ContactsSource,
        session: TandemSession,
        clockEpoch: Instant = Instant.EPOCH,
    ) = ContactsSyncSession(
        source,
        session,
        StandardTestDispatcher(testScheduler),
        TestClock(testScheduler, clockEpoch),
    )

    private fun request(sinceUpdatedAtMs: Long) = contactsSyncRequest { this.sinceUpdatedAtMs = sinceUpdatedAtMs }

    private fun contacts(count: Int): List<Contact> = (1..count).map { contact(it, it.toLong()) }

    private fun contact(
        id: Int,
        updatedAtMs: Long,
    ): Contact =
        contact {
            contactId = id.toString()
            displayName = "Contact $id"
            this.updatedAtMs = updatedAtMs
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
