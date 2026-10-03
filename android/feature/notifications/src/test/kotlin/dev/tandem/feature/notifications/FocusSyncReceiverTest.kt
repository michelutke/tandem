package dev.tandem.feature.notifications

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.focusState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * FocusSyncReceiver tests (E72-04; `docs/planning/backlog/phase-7.yaml` E72-04's `tdd:` list).
 * [FakeTandemSession] scripts incoming `FocusState` frames and records the capability replies;
 * [FakeInterruptionFilterGateway] stands in for `NotificationManager`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FocusSyncReceiverTest {
    @Test
    fun focusSyncReceiver_focusOnMessage_setsInterruptionFilterPriority() =
        runTest {
            val gateway = FakeInterruptionFilterGateway(access = true, initialFilter = InterruptionFilter.ALL)
            val session = startReceiver(gateway)

            session.emitFocus(on = true)
            runCurrent()

            assertEquals(InterruptionFilter.PRIORITY, gateway.filter)
            assertTrue(session.sentFrames.isEmpty())
        }

    @Test
    fun focusSyncReceiver_focusOffMessage_restoresPreviousFilter() =
        runTest {
            val gateway = FakeInterruptionFilterGateway(access = true, initialFilter = InterruptionFilter.ALARMS)
            val session = startReceiver(gateway)

            session.emitFocus(on = true)
            session.emitFocus(on = true)
            session.emitFocus(on = false)
            runCurrent()

            assertEquals(InterruptionFilter.ALARMS, gateway.filter)
            assertEquals(
                listOf(InterruptionFilter.PRIORITY, InterruptionFilter.PRIORITY, InterruptionFilter.ALARMS),
                gateway.appliedFilters,
            )
        }

    @Test
    fun focusSyncReceiver_focusOffWithoutPriorOn_filterUntouched() =
        runTest {
            val gateway = FakeInterruptionFilterGateway(access = true, initialFilter = InterruptionFilter.NONE)
            val session = startReceiver(gateway)

            session.emitFocus(on = false)
            runCurrent()

            assertTrue(gateway.appliedFilters.isEmpty())
        }

    @Test
    fun focusSyncReceiver_policyAccessMissing_filterUntouchedCapabilityUnavailable() =
        runTest {
            val gateway = FakeInterruptionFilterGateway(access = false, initialFilter = InterruptionFilter.ALL)
            val session = startReceiver(gateway)

            session.emitFocus(on = true)
            session.emitFocus(on = false)
            runCurrent()

            assertTrue(gateway.appliedFilters.isEmpty())
            assertEquals(2, session.sentFrames.size)
            session.sentFrames.forEach {
                assertEquals(Channel.CHANNEL_CONTROL, it.channel)
                assertTrue(it.hasFocusSyncCapability())
                assertEquals(false, it.focusSyncCapability.available)
            }
        }

    private fun TestScope.startReceiver(gateway: InterruptionFilterGateway): FakeTandemSession {
        val session = FakeTandemSession()
        backgroundScope.launch { FocusSyncReceiver(session, gateway).run() }
        runCurrent()
        return session
    }

    private fun FakeTandemSession.emitFocus(on: Boolean) {
        emitIncoming(
            envelope {
                channel = Channel.CHANNEL_CONTROL
                focusState = focusState { this.on = on }
            },
        )
    }
}
