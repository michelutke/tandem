package dev.tandem.feature.calls

import dev.tandem.core.testing.ManualElapsedRealtime
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.CallActionErrorCode
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.placeCallRequest
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** PlaceCallHandler tests (E52-05; `docs/planning/backlog/phase-5.yaml` E52-05's `tdd:` list). */
class PlaceCallHandlerTest {
    private val gateway = FakeCallGateway()
    private val permissions = FakeCallPermissions()
    private val notifier = RecordingTapToCallNotifier()
    private val session = FakeTandemSession()
    private val elapsed = ManualElapsedRealtime()
    private val logLines = mutableListOf<String>()
    private var activeSubscriptions = setOf(1, 2)
    private val emergency = setOf("112", "911", "144")

    private fun TestScope.handler() =
        PlaceCallHandler(
            gateway,
            permissions,
            { it in activeSubscriptions },
            notifier,
            { it in emergency },
            session,
            elapsed,
            StandardTestDispatcher(testScheduler),
            { logLines += it },
        )

    private suspend fun PlaceCallHandler.place(
        to: String = "+41791234567",
        subscription: Int = 0,
    ) = handle(
        placeCallRequest {
            requestId = "req-${session.sentFrames.size}"
            address = to
            subscriptionId = subscription
        },
    )

    private val result get() = session.sentFrames.last().callActionResult

    @Test
    fun placeCallHandler_appForegrounded_placesCallDirectly() =
        runTest {
            handler().place("079 123-45 67")

            assertEquals(listOf("0791234567" to 0), gateway.placed)
            assertTrue(result.success)
            assertTrue(notifier.posted.isEmpty())
        }

    @Test
    fun placeCallHandler_backgroundStartBlocked_postsTapToCallAndReturnsNeedsPhoneTap() =
        runTest {
            gateway.placeOutcome = PlaceOutcome.Blocked

            handler().place()

            assertEquals(listOf("+41791234567" to 0), notifier.posted)
            assertEquals(CallActionErrorCode.CALL_ACTION_ERROR_CODE_NEEDS_PHONE_TAP, result.errorCode)
            assertFalse(result.success)
        }

    @Test
    fun placeCallHandler_explicitSubscriptionId_passesMatchingPhoneAccountHandle() =
        runTest {
            handler().place(subscription = 2)

            assertEquals(listOf("+41791234567" to 2), gateway.placed)
        }

    @Test
    fun placeCallHandler_unknownSubscriptionId_returnsInvalidSubscription() =
        runTest {
            handler().place(subscription = 9)

            assertEquals(CallActionErrorCode.CALL_ACTION_ERROR_CODE_INVALID_SUBSCRIPTION, result.errorCode)
            assertTrue(gateway.placed.isEmpty())
        }

    @Test
    fun placeCallHandler_callPhoneDenied_returnsPermissionDenied() =
        runTest {
            permissions.callPhone = false

            handler().place()

            assertEquals(CallActionErrorCode.CALL_ACTION_ERROR_CODE_PERMISSION_DENIED, result.errorCode)
            assertTrue(gateway.placed.isEmpty())
        }

    @Test
    fun placeCallHandler_backgroundPath_logLinesOmitNumber() =
        runTest {
            gateway.placeOutcome = PlaceOutcome.Blocked
            val handler = handler()

            handler.place("+41791234567")
            elapsed.advanceBy(6_000)
            gateway.placeOutcome = PlaceOutcome.Placed
            handler.place("+41791234567")

            assertEquals(2, logLines.size)
            assertTrue(logLines.any { it.contains("tap_to_call") })
            assertFalse(logLines.any { it.contains("4179") })
        }

    @Test
    fun placeCallHandler_mmiCodeAddress_returnsInvalidNumberWithoutCall() =
        runTest {
            val handler = handler()
            listOf("**21*123#", "123,456", "123;456", "*123", "12").forEach { handler.place(it) }

            assertEquals(
                List(5) { CallActionErrorCode.CALL_ACTION_ERROR_CODE_INVALID_NUMBER },
                session.sentFrames.map { it.callActionResult.errorCode },
            )
            assertEquals(5, session.sentFrames.size)
            assertTrue(gateway.placed.isEmpty())
        }

    @Test
    fun placeCallHandler_secondRequestWithin5s_returnsRateLimited() =
        runTest {
            val handler = handler()

            handler.place()
            elapsed.advanceBy(4_999)
            handler.place()
            elapsed.advanceBy(1)
            handler.place()

            assertEquals(
                listOf(
                    CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNSPECIFIED,
                    CallActionErrorCode.CALL_ACTION_ERROR_CODE_RATE_LIMITED,
                    CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNSPECIFIED,
                ),
                session.sentFrames.map { it.callActionResult.errorCode },
            )
            assertEquals(2, gateway.placed.size)
        }

    @Test
    fun placeCallHandler_burstOfFiveInFiveSeconds_placesOneAndRateLimitsRest() =
        runTest {
            val handler = handler()

            repeat(5) {
                handler.place()
                elapsed.advanceBy(900)
            }

            assertEquals(1, gateway.placed.size)
            assertEquals(
                4,
                session.sentFrames.count {
                    it.callActionResult.errorCode == CallActionErrorCode.CALL_ACTION_ERROR_CODE_RATE_LIMITED
                },
            )
        }

    @Test
    fun placeCallHandler_requestArrivesOnCallsChannel_placesIt() =
        runTest {
            val handler = handler()
            backgroundScope.launch { handler.run() }
            runCurrent()

            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CALLS
                    placeCallRequest =
                        placeCallRequest {
                            requestId = "req-9"
                            address = "+41791234567"
                        }
                },
            )
            runCurrent()

            assertEquals(1, gateway.placed.size)
            assertEquals("req-9", result.requestId)
        }

    @Test
    fun placeCallHandler_emergencyNumber_returnsInvalidNumberWithoutCall() =
        runTest {
            val handler = handler()
            handler.place("112")
            elapsed.advanceBy(6_000)
            handler.place("144")

            assertEquals(
                List(2) { CallActionErrorCode.CALL_ACTION_ERROR_CODE_INVALID_NUMBER },
                session.sentFrames.map { it.callActionResult.errorCode },
            )
            assertTrue(gateway.placed.isEmpty())
        }
}
