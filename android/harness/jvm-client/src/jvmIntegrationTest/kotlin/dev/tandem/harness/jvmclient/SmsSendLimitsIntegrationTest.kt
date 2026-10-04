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
import dev.tandem.feature.messaging.SendSmsHandler
import dev.tandem.feature.messaging.SimInfo
import dev.tandem.feature.messaging.SmsSender
import dev.tandem.feature.messaging.SmsSource
import dev.tandem.feature.messaging.SubscriptionSource
import dev.tandem.harness.jvmclient.testserver.AcceptAnyTrustManager
import dev.tandem.harness.jvmclient.testserver.TestIdentity
import dev.tandem.harness.jvmclient.testserver.TestServerKeyManager
import dev.tandem.harness.jvmclient.testserver.TestTlsServer
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.SendSmsErrorCode
import dev.tandem.protocol.v1.SendSmsState
import dev.tandem.protocol.v1.SendSmsStatus
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsThread
import dev.tandem.protocol.v1.sendSmsRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.filter
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
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * E50-11 tdd: security: mitmLab_smsSendBurst20In60s_atMost10SentRestRateLimited and
 * mitmLab_smsBodyOver1600Chars_failedTooLongNoSmsSent.
 *
 * Both limits are enforced by the phone-side [SendSmsHandler] (SPEC.md #sms-channel "Send"; the Mac
 * does not enforce them), so a Mac-vs-harness mitm-lab scenario cannot observe them. The real handler
 * runs against a real [ByteStreamSession] over a Conscrypt mTLS loopback socket to an in-process
 * peer standing in for the Mac (no app launch); a recording [SmsSender] stands in for `SmsManager`.
 */
class SmsSendLimitsIntegrationTest {
    @Test
    fun mitmLab_smsSendBurst20In60s_atMost10SentRestRateLimited() {
        val rig = runScenario(BURST_REQUESTS.map { "burst-$it" to SHORT_BODY }, expectedStatuses = 20)

        assertEquals(10, rig.sender.sent.size)
        val failures = rig.statuses.filter { it.state == SendSmsState.SEND_SMS_STATE_FAILED }
        assertEquals(10, failures.size)
        assertTrue(failures.all { it.errorCode == SendSmsErrorCode.SEND_SMS_ERROR_CODE_RATE_LIMITED })
        assertEquals(10, rig.statuses.count { it.state == SendSmsState.SEND_SMS_STATE_SENDING })
    }

    @Test
    fun mitmLab_smsBodyOver1600Chars_failedTooLongNoSmsSent() {
        val rig = runScenario(listOf("long-1" to "x".repeat(1601)), expectedStatuses = 1)

        assertTrue(rig.sender.sent.isEmpty())
        val status = rig.statuses.single()
        assertEquals("long-1", status.clientMessageId)
        assertEquals(SendSmsState.SEND_SMS_STATE_FAILED, status.state)
        assertEquals(SendSmsErrorCode.SEND_SMS_ERROR_CODE_TOO_LONG, status.errorCode)
    }

    private fun runScenario(
        requests: List<Pair<String, String>>,
        expectedStatuses: Int,
    ): Rig {
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
            val mac = ByteStreamSession(serverStream, Clock.systemUTC(), Dispatchers.IO)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val rig = Rig()
            try {
                runBlocking {
                    withTimeout(SCENARIO_TIMEOUT) {
                        phone.state.first { it is ConnectionState.Ready }
                        mac.state.first { it is ConnectionState.Ready }
                        mac
                            .receive(Channel.CHANNEL_SMS)
                            .filter { it.hasSendSmsStatus() }
                            .onEach { rig.statuses.add(it.sendSmsStatus) }
                            .launchIn(scope)
                        val handler =
                            SendSmsHandler(
                                sender = rig.sender,
                                source = NoProviderSmsSource,
                                session = phone,
                                permission = { true },
                                subscriptions = NoSimSubscriptions,
                                results = MutableSharedFlow<PartResult>(),
                                elapsed = { System.nanoTime() / NANOS_PER_MILLI },
                                ioDispatcher = Dispatchers.IO,
                            )
                        scope.launch { handler.run() }
                        delay(HANDLER_SUBSCRIBE_MILLIS.milliseconds)
                        requests.forEach { (id, body) ->
                            mac.send(Channel.CHANNEL_SMS) {
                                sendSmsRequest =
                                    sendSmsRequest {
                                        clientMessageId = id
                                        address = ADDRESS
                                        this.body = body
                                    }
                            }
                        }
                        while (rig.statuses.size < expectedStatuses) {
                            delay(10.milliseconds)
                        }
                        delay(SETTLE_MILLIS.milliseconds)
                    }
                }
            } finally {
                scope.cancel()
                runCatching { phone.close() }
                runCatching { mac.close() }
            }
            return rig
        }
    }

    private class Rig {
        val sender = RecordingSender()
        val statuses = ConcurrentLinkedQueue<SendSmsStatus>()
    }

    private class RecordingSender : SmsSender {
        val sent = ConcurrentLinkedQueue<OutgoingSms>()

        override fun divide(body: String): List<String> = body.chunked(PART_SIZE)

        override fun send(message: OutgoingSms) {
            sent.add(message)
        }
    }

    private object NoProviderSmsSource : SmsSource {
        override fun threads(): List<SmsThread> = emptyList()

        override fun newerThan(
            sinceId: Long,
            limit: Int,
        ): List<SmsMessage> = emptyList()

        override fun olderThan(
            beforeId: Long,
            limit: Int,
        ): List<SmsMessage> = emptyList()

        override fun maxId(): Long = 0L

        override fun newestOutgoingId(
            address: String,
            afterId: Long,
        ): Long = 1L

        override fun changes(): Flow<Unit> = emptyFlow()
    }

    private object NoSimSubscriptions : SubscriptionSource {
        override fun activeSubscriptions(): List<SimInfo> = emptyList()

        override fun defaultSmsSubscriptionId(): Int = SubscriptionSource.NO_SUBSCRIPTION

        override fun changes(): Flow<Unit> = emptyFlow()
    }

    private companion object {
        const val ADDRESS = "+41790000000"
        const val SHORT_BODY = "hello"
        const val PART_SIZE = 153
        const val NANOS_PER_MILLI = 1_000_000L
        const val HANDLER_SUBSCRIBE_MILLIS = 200L
        const val SETTLE_MILLIS = 500L
        val BURST_REQUESTS = 1..20
        val SCENARIO_TIMEOUT = 60.seconds
    }
}
