package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.tls.SslClientFactory
import dev.tandem.core.transport.tls.SslSocketByteStream
import dev.tandem.feature.contacts.ContactsPage
import dev.tandem.feature.contacts.ContactsSource
import dev.tandem.feature.contacts.ContactsSyncSession
import dev.tandem.harness.jvmclient.testserver.AcceptAnyTrustManager
import dev.tandem.harness.jvmclient.testserver.TestIdentity
import dev.tandem.harness.jvmclient.testserver.TestServerKeyManager
import dev.tandem.harness.jvmclient.testserver.TestTlsServer
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Contact
import dev.tandem.protocol.v1.ContactsSyncResponse
import dev.tandem.protocol.v1.ContactsSyncStatus
import dev.tandem.protocol.v1.contact
import dev.tandem.protocol.v1.contactsSyncRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel as CoroutineChannel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.InetAddress
import java.time.Clock
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource

/**
 * E51-07 tdd: integration: e2eContacts_initialSync_macCacheEqualsFixture and
 * e2eContacts_editThenDelete_reflectedOnMacWithin2s.
 *
 * The real [ContactsSyncSession] (E51-02/05) serves a 500-contact fixture over a real Conscrypt
 * mTLS loopback socket to an in-process [ByteStreamSession] peer standing in for the Mac server
 * (the real Mac app cannot be launched here). [MacContactsCache] applies responses with the same
 * rules as the Swift `ContactsSyncClient`/`ContactsStore` (upsert by id, delete tombstones,
 * Mac-authoritative watermark persisted only on the last page); the Swift side is covered by
 * `ContactsSyncClientTests`/`ContactsStoreContractTests`.
 */
class ContactsSyncIntegrationTest {
    @Test
    fun e2eContacts_initialSync_macCacheEqualsFixture() =
        runScenario { fixture, _, mac ->
            mac.requestSync()
            mac.awaitComplete()

            assertEquals(CONTACT_COUNT, mac.contacts.size)
            assertEquals(fixture.contacts.sortedBy { it.contactId.toLong() }, mac.contacts.values.sortedBy { it.contactId.toLong() })
            assertEquals(fixture.contacts.maxOf { it.updatedAtMs }, mac.watermarkMs)
        }

    @Test
    fun e2eContacts_editThenDelete_reflectedOnMacWithin2s() =
        runScenario { fixture, source, mac ->
            mac.requestSync()
            mac.awaitComplete()
            val responsesBefore = mac.responses.size

            val clock = TimeSource.Monotonic
            val start = clock.markNow()
            fixture.edit("42", "Edited Name")
            fixture.delete("77")
            source.changeEvents.emit(Unit)
            mac.awaitComplete()
            val elapsed = start.elapsedNow()

            assertTrue(elapsed < 2.seconds, "incremental sync took $elapsed")
            assertEquals("Edited Name", mac.contacts.getValue("42").displayName)
            assertEquals(null, mac.contacts["77"])
            assertEquals(CONTACT_COUNT - 1, mac.contacts.size)
            val incremental = mac.responses.drop(responsesBefore)
            assertEquals(1, incremental.size)
            assertEquals(listOf("42"), incremental.single().contactsList.map { it.contactId })
            assertEquals(listOf("77"), incremental.single().deletedContactIdsList)
            assertTrue(incremental.none { it.status == ContactsSyncStatus.CONTACTS_SYNC_STATUS_FULL_RESYNC_REQUIRED })
        }

    private fun runScenario(block: suspend (MutableFixture, MutableFixture.Source, MacContactsCache) -> Unit) {
        HarnessConscryptProvider.ensureInstalled()
        val serverIdentity = TestIdentity("server")
        val clientIdentity = TestIdentity("client")
        val pins = PinSource { listOf(spkiFingerprint(serverIdentity.certificate.publicKey.encoded)) }
        TestTlsServer(TestServerKeyManager(serverIdentity), AcceptAnyTrustManager()).use { server ->
            val accepted = server.acceptSocket()
            val factory =
                SslClientFactory(clientIdentity.keyManager, PinningTrustManager(pins), JvmConscryptSessionTicketDisabler())
            val clientStream = factory.connect(factory.createSocket(), InetAddress.getByName("127.0.0.1"), server.port)
            val serverStream = SslSocketByteStream(accepted.get())
            val phone = ByteStreamSession(clientStream, Clock.systemUTC(), Dispatchers.IO)
            val peer = ByteStreamSession(serverStream, Clock.systemUTC(), Dispatchers.IO)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val fixture = MutableFixture(CONTACT_COUNT, Clock.systemUTC().millis())
            val source = fixture.Source()
            val sync = ContactsSyncSession(source, phone, Dispatchers.IO, Clock.systemUTC())
            val mac = MacContactsCache(peer, scope)
            try {
                runBlocking {
                    withTimeout(SCENARIO_TIMEOUT) {
                        phone.state.first { it is ConnectionState.Ready }
                        peer.state.first { it is ConnectionState.Ready }
                        scope.launch { sync.run() }
                        scope.launch { sync.observeChanges() }
                        block(fixture, source, mac)
                    }
                }
            } finally {
                scope.cancel()
                runCatching { phone.close() }
                runCatching { peer.close() }
            }
        }
    }

    private class MacContactsCache(
        private val peer: TandemSession,
        scope: CoroutineScope,
    ) {
        val contacts = HashMap<String, Contact>()
        val responses = mutableListOf<ContactsSyncResponse>()
        var watermarkMs = 0L
            private set
        private val completions = CoroutineChannel<Unit>(CoroutineChannel.UNLIMITED)

        init {
            peer
                .receive(Channel.CHANNEL_CONTACTS)
                .onEach { envelope ->
                    if (!envelope.hasContactsSyncResponse()) return@onEach
                    val response = envelope.contactsSyncResponse
                    synchronized(this) {
                        responses += response
                        response.contactsList.forEach { contacts[it.contactId] = it }
                        response.deletedContactIdsList.forEach { contacts.remove(it) }
                        if (response.complete) watermarkMs = response.watermarkMs
                    }
                    if (response.complete) completions.trySend(Unit)
                }.launchIn(scope)
        }

        suspend fun requestSync() {
            peer.send(Channel.CHANNEL_CONTACTS) {
                contactsSyncRequest = contactsSyncRequest { sinceUpdatedAtMs = watermarkMs }
            }
        }

        suspend fun awaitComplete() = completions.receive()
    }

    private class MutableFixture(
        count: Int,
        private val nowMs: Long,
    ) {
        private val byId =
            (1..count)
                .map { id ->
                    contact {
                        contactId = id.toString()
                        displayName = "Contact $id"
                        phoneNumbers +=
                            Contact.PhoneNumber
                                .newBuilder()
                                .setNumber("+4179${(1_000_000 + id)}")
                                .setNormalizedE164("+4179${(1_000_000 + id)}")
                                .build()
                        emails += Contact.Email.newBuilder().setAddress("c$id@example.com").build()
                        updatedAtMs = nowMs - 3_600_000 + id
                    }
                }.associateBy { it.contactId }
                .toMutableMap()
        private val deleted = mutableListOf<String>()

        val contacts: List<Contact> get() = synchronized(this) { byId.values.toList() }

        fun edit(
            id: String,
            name: String,
        ) = synchronized(this) {
            byId[id] = byId.getValue(id).toBuilder().setDisplayName(name).setUpdatedAtMs(System.currentTimeMillis()).build()
        }

        fun delete(id: String) =
            synchronized(this) {
                byId.remove(id)
                deleted += id
            }

        inner class Source : ContactsSource {
            val changeEvents = MutableSharedFlow<Unit>(extraBufferCapacity = 64)

            override fun hasReadPermission() = true

            override fun readPage(
                afterContactId: Long,
                sinceUpdatedAtMs: Long,
            ): ContactsPage =
                synchronized(this@MutableFixture) {
                    val remaining =
                        byId.values
                            .filter { it.contactId.toLong() > afterContactId && it.updatedAtMs > sinceUpdatedAtMs }
                            .sortedBy { it.contactId.toLong() }
                    val page = remaining.take(ContactsSource.PAGE_SIZE)
                    ContactsPage(page, if (remaining.size > page.size) page.last().contactId.toLong() else null)
                }

            override fun readDeletedContactIds(sinceDeletedAtMs: Long): List<String> =
                synchronized(this@MutableFixture) { deleted.toList() }

            override fun changes(): Flow<Unit> = changeEvents
        }
    }

    private companion object {
        const val CONTACT_COUNT = 500
        val SCENARIO_TIMEOUT = 60.seconds
    }
}
