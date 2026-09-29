package dev.tandem.feature.notifications

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.NotificationActionResult
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.notificationAction
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

/**
 * `startNotificationActionReader` tests (E30-09 `tdd:`). Robolectric (E00-20):
 * [NotificationActionExecutor] takes a real [Context], the same reason
 * `NotificationActionExecutorTest` needs it.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class NotificationActionReaderTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun androidActionReply_actionReceived_sendsResultBackOnNotifyChannel() =
        runTest {
            val session = FakeTandemSession()
            val executor = NotificationActionExecutor(context) { null }
            // backgroundScope: the reader's `collect` never completes on its own (mirrors
            // production, where it runs until the session's receive flow finishes) -- runTest
            // would otherwise hang waiting for it to finish alongside the test body.
            startNotificationActionReader(backgroundScope, session, executor)

            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_NOTIFY
                    notificationAction =
                        notificationAction {
                            key = "unknown-key"
                            actionIndex = 0
                        }
                },
            )
            runCurrent()

            val sent = session.sentFrames.single { it.payloadCase == Envelope.PayloadCase.NOTIFICATION_ACTION_RESULT }
            assertEquals("unknown-key", sent.notificationActionResult.key)
            assertEquals(NotificationActionResult.Status.STATUS_GONE, sent.notificationActionResult.status)
        }
}
