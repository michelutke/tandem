package dev.tandem.core.transport

import app.cash.turbine.test
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * [FakeTandemSession] tests (E12-11; `docs/planning/backlog/phase-1.yaml` E12-11's `tdd:` list).
 */
class FakeTandemSessionTest {
    @Test
    fun fakeTandemSession_sendCalls_recordedInOrder() =
        runTest {
            val fake = FakeTandemSession()

            fake.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
            fake.send(Channel.CHANNEL_FILES) { deviceStatus = DeviceStatus.getDefaultInstance() }
            fake.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }

            assertEquals(
                listOf(Channel.CHANNEL_NOTIFY, Channel.CHANNEL_FILES, Channel.CHANNEL_NOTIFY),
                fake.sentFrames.map { it.channel },
            )
        }

    @Test
    fun fakeTandemSession_injectedIncomingFrame_emittedOnReceiveFlow() =
        runTest {
            val fake = FakeTandemSession()
            val frame =
                envelope {
                    channel = Channel.CHANNEL_NOTIFY
                    seq = 1
                    deviceStatus = DeviceStatus.getDefaultInstance()
                }

            fake.receive(Channel.CHANNEL_NOTIFY).test {
                fake.emitIncoming(frame)
                assertEquals(frame, awaitItem())
                cancelAndIgnoreRemainingEvents()
            }
        }
}
