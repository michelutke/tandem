package dev.tandem.app.connection.feature

import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.feature.notifications.CoalescingNotificationEventSink
import dev.tandem.feature.notifications.LiveNotificationEventSink
import dev.tandem.feature.notifications.NotificationEventSink
import dev.tandem.feature.notifications.NotificationSink
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.awaitCancellation
import java.time.Clock

/** Points the notification listener at a NOTIFY-sending sink for the attached session (F-5.1). */
class NotificationsFeature(
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    private val clock: Clock,
    private val dispatcher: CoroutineDispatcher,
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        val sink = NotificationSink(session, elapsedRealtimeSource, dispatcher)
        val coalescing = CoalescingNotificationEventSink(sink, clock, dispatcher)
        LiveNotificationEventSink.target = coalescing
        try {
            awaitCancellation()
        } finally {
            LiveNotificationEventSink.target = NotificationEventSink.NoOp
            coalescing.close()
            sink.close()
        }
    }
}
