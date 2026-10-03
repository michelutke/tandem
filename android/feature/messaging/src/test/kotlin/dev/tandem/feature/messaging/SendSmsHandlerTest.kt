package dev.tandem.feature.messaging

import android.app.Activity
import android.telephony.SmsManager
import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.SendSmsErrorCode
import dev.tandem.protocol.v1.SendSmsState
import dev.tandem.protocol.v1.SendSmsStatus
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsMessageType
import dev.tandem.protocol.v1.sendSmsRequest
import dev.tandem.protocol.v1.smsMessage
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** SendSmsHandler tests (E50-04; `docs/planning/backlog/phase-5.yaml` E50-04's `tdd:` list). */
@OptIn(ExperimentalCoroutinesApi::class)
class SendSmsHandlerTest {
    @Test
    fun sendSmsHandler_sendSmsNotGranted_failsPermissionDeniedWithoutSending() =
        runTest {
            val rig = Rig(permitted = false)

            rig.handler(this).handle(request())

            assertTrue(rig.sender.sent.isEmpty())
            assertEquals(
                listOf(failed(SendSmsErrorCode.SEND_SMS_ERROR_CODE_PERMISSION_REQUIRED)),
                rig.statuses().map { it.state to it.errorCode },
            )
        }

    @Test
    fun sendSmsHandler_systemProviderRowPresent_reportsProviderMessageId() =
        runTest {
            val rig = Rig(rows = listOf(row(id = 3, type = SmsMessageType.SMS_MESSAGE_TYPE_SENT)))
            val job = launch { rig.handler(this@runTest).handle(request()) }
            runCurrent()
            rig.source.messages += row(id = 7, type = SmsMessageType.SMS_MESSAGE_TYPE_SENT)

            rig.results.emit(part(0, SendResultKind.SENT))
            rig.results.emit(part(1, SendResultKind.SENT))
            runCurrent()
            job.cancelAndJoin()

            val sent = rig.statuses().single { it.state == SendSmsState.SEND_SMS_STATE_SENT }
            assertEquals(7L, sent.providerMessageId)
            assertEquals("client-1", sent.clientMessageId)
            assertEquals(1, rig.sender.sent.size)
            assertEquals(
                2,
                rig.sender.sent
                    .single()
                    .parts.size,
            )
        }

    @Test
    fun sendSmsHandler_noProviderRowWithin5s_reportsProviderMessageIdZero() =
        runTest {
            val rig = Rig()
            val job = launch { rig.handler(this@runTest).handle(request()) }
            runCurrent()
            rig.results.emit(part(0, SendResultKind.SENT))
            rig.results.emit(part(1, SendResultKind.SENT))

            advanceTimeBy(5_001)
            runCurrent()
            job.cancelAndJoin()

            assertEquals(0L, rig.statuses().single { it.state == SendSmsState.SEND_SMS_STATE_SENT }.providerMessageId)
        }

    @Test
    fun sendFailureLogging_radioOffResult_logLinesOmitBodyAndAddress() =
        runTest {
            val rig = Rig()
            val job = launch { rig.handler(this@runTest).handle(request()) }
            runCurrent()

            rig.results.emit(part(0, SendResultKind.SENT, SmsManager.RESULT_ERROR_RADIO_OFF))
            runCurrent()
            job.join()

            assertTrue(rig.logLines.isNotEmpty())
            assertTrue(rig.logLines.all { !it.contains(BODY) && !it.contains(ADDRESS) })
            assertTrue(
                rig.logLines.any { it.contains("client-1") && it.contains("${SmsManager.RESULT_ERROR_RADIO_OFF}") },
            )
            assertEquals(
                SendSmsErrorCode.SEND_SMS_ERROR_CODE_RADIO_OFF,
                rig.statuses().single { it.state == SendSmsState.SEND_SMS_STATE_FAILED }.errorCode,
            )
        }

    @Test
    fun sendSmsHandler_bodyOver1600Chars_failsTooLongWithoutSending() =
        runTest {
            val rig = Rig()

            rig.handler(this).handle(request(body = "a".repeat(1601)))

            assertTrue(rig.sender.sent.isEmpty())
            assertEquals(
                listOf(failed(SendSmsErrorCode.SEND_SMS_ERROR_CODE_TOO_LONG)),
                rig.statuses().map {
                    it.state to
                        it.errorCode
                },
            )
        }

    @Test
    fun sendSmsHandler_invalidAddress_failsInvalidAddressWithoutSending() =
        runTest {
            val rig = Rig()

            rig.handler(this).handle(request(address = "12;34"))

            assertTrue(rig.sender.sent.isEmpty())
            assertEquals(
                listOf(failed(SendSmsErrorCode.SEND_SMS_ERROR_CODE_INVALID_ADDRESS)),
                rig.statuses().map {
                    it.state to
                        it.errorCode
                },
            )
        }

    @Test
    fun sendSmsHandler_eleventhSendWithin60s_failsRateLimited() =
        runTest {
            val rig = Rig()
            val handler = rig.handler(this)
            val inFlight = List(10) { launch { handler.handle(request(id = "c$it")) } }
            runCurrent()
            val sendsBefore = rig.sender.sent.size

            handler.handle(request(id = "c10"))

            assertEquals(10, sendsBefore)
            assertEquals(10, rig.sender.sent.size)
            val last = rig.statuses().last()
            inFlight.forEach { it.cancel() }
            assertEquals("c10", last.clientMessageId)
            assertEquals(SendSmsErrorCode.SEND_SMS_ERROR_CODE_RATE_LIMITED, last.errorCode)
        }

    private fun failed(code: SendSmsErrorCode) = SendSmsState.SEND_SMS_STATE_FAILED to code

    private fun request(
        id: String = "client-1",
        address: String = ADDRESS,
        body: String = BODY.repeat(5),
    ) = sendSmsRequest {
        clientMessageId = id
        this.address = address
        this.body = body
    }

    private fun part(
        index: Int,
        kind: SendResultKind,
        resultCode: Int = Activity.RESULT_OK,
    ) = PartResult("client-1", index, kind, resultCode)

    private fun row(
        id: Long,
        type: SmsMessageType,
    ) = smsMessage {
        this.id = id
        address = ADDRESS
        this.type = type
    }

    private class Rig(
        permitted: Boolean = true,
        rows: List<SmsMessage> = emptyList(),
    ) {
        val session = FakeTandemSession()
        val sender = RecordingSmsSender(partSize = 30)
        val results = MutableSharedFlow<PartResult>(extraBufferCapacity = 64)
        val logLines = mutableListOf<String>()
        val source = FakeSmsSource(messages = rows)
        private val grant = SendSmsPermission { permitted }

        fun handler(scope: TestScope): SendSmsHandler {
            val scheduler = scope.testScheduler
            return SendSmsHandler(
                sender = sender,
                source = source,
                session = session,
                permission = grant,
                results = results,
                elapsed = FakeElapsedRealtime(scheduler),
                ioDispatcher = StandardTestDispatcher(scheduler),
                log = { logLines += it },
            )
        }

        fun statuses(): List<SendSmsStatus> =
            session.sentFrames.filter { it.hasSendSmsStatus() }.map { it.sendSmsStatus }
    }

    private companion object {
        const val ADDRESS = "+41790000000"
        const val BODY = "secret body "
    }
}
