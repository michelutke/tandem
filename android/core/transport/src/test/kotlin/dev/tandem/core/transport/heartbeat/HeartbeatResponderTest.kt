package dev.tandem.core.transport.heartbeat

import dev.tandem.core.protocol.multiplex.FrameArrival
import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.protocol.v1.Channel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * [HeartbeatResponder] tests (E20-15; `docs/planning/backlog/phase-2.yaml` E20-15's `tdd:` list).
 * [received] is a plain [MutableSharedFlow] standing in for
 * `dev.tandem.core.protocol.multiplex.ChannelMultiplexer.received`; every test shares its
 * `runTest` scope's `StandardTestDispatcher` so [FakeElapsedRealtime] and the dispatcher advance
 * together (E00-18).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class HeartbeatResponderTest {
    @Test
    fun heartbeatResponder_macHeartbeatReceived_repliesWithin1s() =
        runTest {
            val received = MutableSharedFlow<FrameArrival>()
            var replyCount = 0
            val responder =
                HeartbeatResponder(
                    received = received,
                    sendHeartbeat = { replyCount++ },
                    elapsedRealtimeSource = FakeElapsedRealtime(testScheduler),
                    dispatcher = StandardTestDispatcher(testScheduler),
                )
            responder.start()
            runCurrent()

            received.emit(FrameArrival(Channel.CHANNEL_CONTROL, isHeartbeat = true))
            advanceTimeBy(1.seconds)
            runCurrent()

            assertEquals(1, replyCount)
        }

    @Test
    fun heartbeatResponder_nonHeartbeatFrame_noReplySent() =
        runTest {
            val received = MutableSharedFlow<FrameArrival>()
            var replyCount = 0
            val responder =
                HeartbeatResponder(
                    received = received,
                    sendHeartbeat = { replyCount++ },
                    elapsedRealtimeSource = FakeElapsedRealtime(testScheduler),
                    dispatcher = StandardTestDispatcher(testScheduler),
                )
            responder.start()
            runCurrent()

            received.emit(FrameArrival(Channel.CHANNEL_NOTIFY, isHeartbeat = false))
            received.emit(FrameArrival(Channel.CHANNEL_CONTROL, isHeartbeat = false))
            runCurrent()

            assertEquals(0, replyCount)
        }

    @Test
    fun heartbeatResponder_hundredHeartbeatsIn1s_atMostOneReplyPerSecond() =
        runTest {
            val received = MutableSharedFlow<FrameArrival>()
            var replyCount = 0
            val responder =
                HeartbeatResponder(
                    received = received,
                    sendHeartbeat = { replyCount++ },
                    elapsedRealtimeSource = FakeElapsedRealtime(testScheduler),
                    dispatcher = StandardTestDispatcher(testScheduler),
                )
            responder.start()
            runCurrent()

            repeat(HEARTBEAT_COUNT) {
                received.emit(FrameArrival(Channel.CHANNEL_CONTROL, isHeartbeat = true))
                advanceTimeBy(SPACING_MILLIS.milliseconds) // 100 * 9ms = 900ms: all inside the same 1s window.
                runCurrent()
            }

            assertEquals(1, replyCount)
        }

    private companion object {
        const val HEARTBEAT_COUNT = 100
        const val SPACING_MILLIS = 9L
    }
}
