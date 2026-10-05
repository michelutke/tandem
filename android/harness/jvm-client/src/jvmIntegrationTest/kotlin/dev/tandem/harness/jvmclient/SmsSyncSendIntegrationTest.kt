package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.tls.SslClientFactory
import dev.tandem.core.transport.tls.SslSocketByteStream
import dev.tandem.feature.messaging.OutgoingSms
import dev.tandem.feature.messaging.PartResult
import dev.tandem.feature.messaging.SendResultKind
import dev.tandem.feature.messaging.SendSmsHandler
import dev.tandem.feature.messaging.SimInfo
import dev.tandem.feature.messaging.SmsIncrementalSync
import dev.tandem.feature.messaging.SmsSender
import dev.tandem.feature.messaging.SmsSource
import dev.tandem.feature.messaging.SmsSyncSession
import dev.tandem.feature.messaging.SubscriptionSource
import dev.tandem.harness.jvmclient.testserver.AcceptAnyTrustManager
import dev.tandem.harness.jvmclient.testserver.TestIdentity
import dev.tandem.harness.jvmclient.testserver.TestServerKeyManager
import dev.tandem.harness.jvmclient.testserver.TestTlsServer
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.SendSmsState
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsMessageType
import dev.tandem.protocol.v1.SmsSyncResponse
import dev.tandem.protocol.v1.SmsSyncStatus
import dev.tandem.protocol.v1.SmsThread
import dev.tandem.protocol.v1.sendSmsRequest
import dev.tandem.protocol.v1.smsMessage
import dev.tandem.protocol.v1.smsSyncRequest
import dev.tandem.protocol.v1.smsThread
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.emptyFlow
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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource

/**
 * E50-10 tdd: integration: e2eSms_fiveThousandFixtureInitialSync_macStoreHas5000UniqueMessages,
 * e2eSms_disconnectAfterPageTen_macStoreEndsWithExactly5000,
 * e2eSms_fakeSourceInsert_visibleInMacStoreWithin2s and e2eSms_sendFromMac_deliveredStateStoredOnMac.
 *
 * The real [SmsSyncSession] (E50-13), [SmsIncrementalSync] (E50-03) and [SendSmsHandler] (E50-04) run
 * against a 5k-message fixture source and a recording sender, over real Conscrypt mTLS loopback sockets
 * to an in-process [ByteStreamSession] peer standing in for the Mac (same approach as
 * `ContactsSyncIntegrationTest`; the real Mac app cannot be launched here). [MacSmsMirror] applies pages
 * with the rules of the Swift `SmsSyncClient` (cursor fields left unset keep the stored value, backfill
 * completion is sticky, a page with a moved backfill cursor triggers the next request); the Swift side
 * is covered by `SmsSyncClientTests`. The physical-phone gates are `manual:` tests.
 */
class SmsSyncSendIntegrationTest {
    @Test
    fun e2eSms_fiveThousandFixtureInitialSync_macStoreHas5000UniqueMessages() =
        runScenario { rig ->
            val link = rig.connect()
            rig.mac.attach(link.mac)
            rig.mac.requestSync()
            rig.mac.awaitComplete()

            assertEquals(MESSAGE_COUNT, rig.mac.messages.size)
            assertEquals(MESSAGE_COUNT.toLong(), rig.mac.highWatermarkId)
        }

    @Test
    fun e2eSms_disconnectAfterPageTen_macStoreEndsWithExactly5000() =
        runScenario { rig ->
            val first = rig.connect()
            val firstAttachment = rig.mac.attach(first.mac)
            rig.mac.onPageApplied = { pages ->
                if (pages == DROP_AFTER_PAGES) {
                    firstAttachment.cancel()
                    first.close()
                }
            }
            rig.mac.requestSync()
            first.phone.state.first { it is ConnectionState.Disconnected || it is ConnectionState.Failed }
            assertTrue(rig.mac.messages.size < MESSAGE_COUNT, "the drop must interrupt the sync")
            assertTrue(rig.mac.pagesApplied >= DROP_AFTER_PAGES)

            val second = rig.connect()
            rig.mac.attach(second.mac)
            rig.mac.requestSync()
            rig.mac.awaitComplete()

            assertEquals(MESSAGE_COUNT, rig.mac.messages.size)
        }

    @Test
    fun e2eSms_fakeSourceInsert_visibleInMacStoreWithin2s() =
        runScenario { rig ->
            val link = rig.connect()
            rig.mac.attach(link.mac)
            rig.mac.requestSync()
            rig.mac.awaitComplete()
            rig.scope.launch { SmsIncrementalSync(rig.source, link.phone, Dispatchers.IO).run { rig.source.maxId() } }
            delay(SUBSCRIBE_MILLIS.milliseconds)

            val start = TimeSource.Monotonic.markNow()
            val insertedId = rig.source.insert("+41791234567", "fresh inbound", SmsMessageType.SMS_MESSAGE_TYPE_INBOX)
            while (!rig.mac.messages.containsKey(insertedId)) delay(POLL_MILLIS.milliseconds)
            val elapsed = start.elapsedNow()

            assertTrue(elapsed < 2.seconds, "incremental push took $elapsed")
            assertEquals("fresh inbound", rig.mac.messages.getValue(insertedId).body)
            assertEquals(MESSAGE_COUNT + 1, rig.mac.messages.size)
        }

    @Test
    fun e2eSms_sendFromMac_deliveredStateStoredOnMac() =
        runScenario { rig ->
            val link = rig.connect()
            rig.mac.attach(link.mac)
            val handler =
                SendSmsHandler(
                    sender = rig.sender,
                    source = rig.source,
                    session = link.phone,
                    permission = { true },
                    subscriptions = NoSimSubscriptions,
                    results = rig.partResults,
                    elapsed = { System.nanoTime() / NANOS_PER_MILLI },
                    ioDispatcher = Dispatchers.IO,
                )
            rig.scope.launch { handler.run() }
            delay(SUBSCRIBE_MILLIS.milliseconds)

            val start = TimeSource.Monotonic.markNow()
            rig.mac.send("compose-1", RECIPIENT, COMPOSED_BODY)
            val delivered = rig.mac.awaitState("compose-1", SendSmsState.SEND_SMS_STATE_DELIVERED)
            val elapsed = start.elapsedNow()

            assertTrue(delivered)
            assertTrue(elapsed < 2.seconds, "send round trip took $elapsed")
            val sent = rig.sender.sent.single()
            assertEquals(RECIPIENT, sent.destination)
            assertEquals(COMPOSED_BODY, sent.parts.joinToString(""))
            assertEquals(
                listOf(
                    SendSmsState.SEND_SMS_STATE_SENDING,
                    SendSmsState.SEND_SMS_STATE_SENT,
                    SendSmsState.SEND_SMS_STATE_DELIVERED,
                ),
                rig.mac.statesOf("compose-1"),
            )
        }

    private fun runScenario(block: suspend (Rig) -> Unit) {
        HarnessConscryptProvider.ensureInstalled()
        val serverIdentity = TestIdentity("server")
        val clientIdentity = TestIdentity("client")
        val pins = PinSource { listOf(spkiFingerprint(serverIdentity.certificate.publicKey.encoded)) }
        TestTlsServer(TestServerKeyManager(serverIdentity), AcceptAnyTrustManager()).use { server ->
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val rig = Rig(server, clientIdentity, pins, scope)
            try {
                runBlocking { withTimeout(SCENARIO_TIMEOUT) { block(rig) } }
            } finally {
                scope.cancel()
                rig.links.forEach { it.close() }
            }
        }
    }

    private class Link(
        val phone: ByteStreamSession,
        val mac: ByteStreamSession,
    ) {
        fun close() {
            runCatching { phone.close() }
            runCatching { mac.close() }
        }
    }

    private class Rig(
        private val server: TestTlsServer,
        private val clientIdentity: TestIdentity,
        private val pins: PinSource,
        val scope: CoroutineScope,
    ) {
        val source = FixtureSmsSource(MESSAGE_COUNT)
        val partResults = MutableSharedFlow<PartResult>(extraBufferCapacity = PART_RESULT_BUFFER)
        val sender = ResultReportingSender(source, partResults)
        val mac = MacSmsMirror()
        val links = mutableListOf<Link>()

        /** Dials a fresh mTLS connection and starts the phone's [SmsSyncSession] on it. */
        suspend fun connect(): Link {
            val accepted = server.acceptSocket()
            val factory =
                SslClientFactory(clientIdentity.keyManager, PinningTrustManager(pins), JvmConscryptSessionTicketDisabler())
            val clientStream = factory.connect(factory.createSocket(), InetAddress.getByName("127.0.0.1"), server.port)
            val phone = ByteStreamSession(clientStream, Clock.systemUTC(), Dispatchers.IO)
            val macSession = ByteStreamSession(SslSocketByteStream(accepted.get()), Clock.systemUTC(), Dispatchers.IO)
            val link = Link(phone, macSession).also { links += it }
            phone.state.first { it is ConnectionState.Ready }
            macSession.state.first { it is ConnectionState.Ready }
            scope.launch { SmsSyncSession(source, phone, Dispatchers.IO).run() }
            return link
        }
    }

    private class MacSmsMirror {
        val messages = ConcurrentHashMap<Long, SmsMessage>()
        private val threads = ConcurrentHashMap<Long, SmsThread>()
        private val states = ConcurrentHashMap<String, MutableList<SendSmsState>>()
        private val completion = CompletableDeferred<Unit>()
        private var session: ByteStreamSession? = null

        @Volatile var highWatermarkId = 0L
            private set

        @Volatile private var backfillCursorId = 0L

        @Volatile private var backfillComplete = false

        @Volatile var pagesApplied = 0
            private set

        @Volatile var onPageApplied: (Int) -> Unit = {}

        /** Starts applying the SMS channel of [mac] (the previous attachment, if any, is the caller's to cancel). */
        fun attach(mac: ByteStreamSession): Job {
            session = mac
            return mac
                .receive(Channel.CHANNEL_SMS)
                .onEach { envelope ->
                    if (envelope.hasSmsSyncResponse()) apply(envelope.smsSyncResponse)
                    if (envelope.hasSendSmsStatus()) {
                        states.getOrPut(envelope.sendSmsStatus.clientMessageId) { mutableListOf() }
                            .let { synchronized(it) { it += envelope.sendSmsStatus.state } }
                    }
                }.launchIn(CoroutineScope(SupervisorJob() + Dispatchers.Default))
        }

        suspend fun requestSync() {
            val current = session ?: return
            runCatching {
                current.send(Channel.CHANNEL_SMS) {
                    smsSyncRequest =
                        smsSyncRequest {
                            sinceId = highWatermarkId
                            backfillBeforeId = backfillCursorId
                        }
                }
            }
        }

        suspend fun awaitComplete() = completion.await()

        suspend fun send(
            clientMessageId: String,
            address: String,
            body: String,
        ) {
            states[clientMessageId] = mutableListOf()
            requireNotNull(session).send(Channel.CHANNEL_SMS) {
                sendSmsRequest =
                    sendSmsRequest {
                        this.clientMessageId = clientMessageId
                        this.address = address
                        this.body = body
                    }
            }
        }

        suspend fun awaitState(
            clientMessageId: String,
            state: SendSmsState,
        ): Boolean {
            while (state !in statesOf(clientMessageId)) delay(POLL_MILLIS.milliseconds)
            return true
        }

        fun statesOf(clientMessageId: String): List<SendSmsState> =
            states[clientMessageId]?.let { synchronized(it) { it.toList() } } ?: emptyList()

        private suspend fun apply(response: SmsSyncResponse) {
            if (response.status != SmsSyncStatus.SMS_SYNC_STATUS_OK) return
            val previousHigh = highWatermarkId
            val previousCursor = backfillCursorId
            response.threadsList.forEach { threads[it.threadId] = it }
            response.messagesList.forEach { messages[it.id] = it }
            if (response.highWatermarkId != 0L) highWatermarkId = response.highWatermarkId
            if (response.backfillCursorId != 0L) backfillCursorId = response.backfillCursorId
            backfillComplete = backfillComplete || response.backfillComplete
            val pages = ++pagesApplied
            onPageApplied(pages)
            when {
                backfillComplete -> completion.complete(Unit)
                response.backfillCursorId != 0L && (highWatermarkId != previousHigh || backfillCursorId != previousCursor) -> requestSync()
            }
        }
    }

    private class FixtureSmsSource(
        count: Int,
    ) : SmsSource {
        private val rows = java.util.TreeMap<Long, SmsMessage>()
        private val changeEvents = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

        init {
            (1..count).forEach { id -> rows[id.toLong()] = inboundRow(id.toLong(), "+4179${1_000_000 + id % THREAD_COUNT}", "message $id") }
        }

        fun insert(
            address: String,
            body: String,
            type: SmsMessageType,
        ): Long =
            synchronized(this) {
                val id = (rows.lastKey() + 1)
                rows[id] = inboundRow(id, address, body).toBuilder().setType(type).build()
                id
            }.also { changeEvents.tryEmit(Unit) }

        override fun threads(): List<SmsThread> =
            synchronized(this) {
                rows.values
                    .groupBy { it.threadId }
                    .map { (threadId, messages) ->
                        smsThread {
                            this.threadId = threadId
                            address = messages.first().address
                            snippet = messages.last().body
                            lastMessageAtMs = messages.maxOf { it.timestampMs }
                        }
                    }
            }

        override fun newerThan(
            sinceId: Long,
            limit: Int,
        ): List<SmsMessage> = synchronized(this) { rows.tailMap(sinceId, false).values.take(limit) }

        override fun olderThan(
            beforeId: Long,
            limit: Int,
        ): List<SmsMessage> = synchronized(this) { rows.headMap(beforeId, false).descendingMap().values.take(limit) }

        override fun maxId(): Long = synchronized(this) { rows.lastKey() }

        override fun newestOutgoingId(
            address: String,
            afterId: Long,
        ): Long =
            synchronized(this) {
                rows
                    .tailMap(afterId, false)
                    .values
                    .lastOrNull { it.address == address && it.type == SmsMessageType.SMS_MESSAGE_TYPE_SENT }
                    ?.id ?: 0L
            }

        override fun changes(): Flow<Unit> = changeEvents

        private fun inboundRow(
            id: Long,
            address: String,
            body: String,
        ): SmsMessage =
            smsMessage {
                this.id = id
                threadId = address.takeLast(THREAD_DIGITS).toLong()
                this.address = address
                this.body = body
                timestampMs = BASE_TIMESTAMP_MS + id
                type = SmsMessageType.SMS_MESSAGE_TYPE_INBOX
            }
    }

    /** Stands in for `SmsManager`: records the send, writes the SENT provider row, reports sent and delivered per part. */
    private class ResultReportingSender(
        private val source: FixtureSmsSource,
        private val results: MutableSharedFlow<PartResult>,
    ) : SmsSender {
        val sent = ConcurrentLinkedQueue<OutgoingSms>()

        override fun divide(body: String): List<String> = body.chunked(PART_SIZE)

        override fun send(message: OutgoingSms) {
            sent.add(message)
            source.insert(message.destination, message.parts.joinToString(""), SmsMessageType.SMS_MESSAGE_TYPE_SENT)
            message.parts.indices.forEach { index ->
                results.tryEmit(PartResult(message.clientMessageId, index, SendResultKind.SENT, ACTIVITY_RESULT_OK))
                results.tryEmit(PartResult(message.clientMessageId, index, SendResultKind.DELIVERED, ACTIVITY_RESULT_OK))
            }
        }
    }

    private object NoSimSubscriptions : SubscriptionSource {
        override fun activeSubscriptions(): List<SimInfo> = emptyList()

        override fun defaultSmsSubscriptionId(): Int = SubscriptionSource.NO_SUBSCRIPTION

        override fun changes(): Flow<Unit> = emptyFlow()
    }

    private companion object {
        const val MESSAGE_COUNT = 5_000
        const val DROP_AFTER_PAGES = 10
        const val THREAD_COUNT = 40
        const val THREAD_DIGITS = 7
        const val BASE_TIMESTAMP_MS = 1_700_000_000_000L
        const val RECIPIENT = "+41790000000"
        const val COMPOSED_BODY = "Hello from the Mac, composed in the thread view"
        const val PART_SIZE = 153
        const val PART_RESULT_BUFFER = 64
        const val ACTIVITY_RESULT_OK = -1
        const val NANOS_PER_MILLI = 1_000_000L
        const val SUBSCRIBE_MILLIS = 300L
        const val POLL_MILLIS = 10L
        val SCENARIO_TIMEOUT = 60.seconds
    }
}
