package dev.tandem.feature.notifications

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.notificationDismiss
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * `startNotificationDismissReader` tests (E30-10 `tdd:`). Plain JUnit5 (repo Robolectric rule):
 * this reader touches no Android framework type, only [FakeTandemSession] (E12-11) and protocol
 * types, so Robolectric would be pure overhead here.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NotificationDismissReaderTest {
    @Test
    fun androidDismissSync_macOriginDismissReceived_callsCancelNotificationWithKey() =
        runTest {
            val session = FakeTandemSession()
            val cancelled = mutableListOf<String>()
            // backgroundScope: the reader's `collect` never completes on its own (mirrors
            // production, where it runs until the session's receive flow finishes) -- runTest
            // would otherwise hang waiting for it to finish alongside the test body.
            startNotificationDismissReader(backgroundScope, session, cancelled::add)

            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_NOTIFY
                    notificationDismiss =
                        notificationDismiss {
                            key = "mac-dismissed-key"
                            origin = NotificationDismiss.Origin.ORIGIN_MACOS
                        }
                },
            )
            runCurrent()

            assertEquals(listOf("mac-dismissed-key"), cancelled)
        }

    @Test
    fun androidDismissSync_androidOriginDismissReceived_doesNotCallCancelNotification() =
        runTest {
            val session = FakeTandemSession()
            val cancelled = mutableListOf<String>()
            startNotificationDismissReader(backgroundScope, session, cancelled::add)

            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_NOTIFY
                    notificationDismiss =
                        notificationDismiss {
                            key = "phone-dismissed-key"
                            origin = NotificationDismiss.Origin.ORIGIN_ANDROID
                        }
                },
            )
            runCurrent()

            assertTrue(cancelled.isEmpty())
        }
}
