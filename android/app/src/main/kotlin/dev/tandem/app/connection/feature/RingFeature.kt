package dev.tandem.app.connection.feature

import dev.tandem.app.connection.SessionFeature
import dev.tandem.app.ring.AlarmPlayer
import dev.tandem.app.ring.LiveRingController
import dev.tandem.app.ring.NotificationPolicyAccess
import dev.tandem.app.ring.RingController
import dev.tandem.app.ring.RingHandler
import dev.tandem.app.ring.RingNotifier
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.Channel
import kotlinx.coroutines.coroutineScope

/** Rings the phone on the Mac's `Ring` and stops on `RingStop` (F-4.4); the alarm never outlives the session. */
class RingFeature(
    private val alarmPlayer: () -> AlarmPlayer,
    private val policyAccess: () -> NotificationPolicyAccess,
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    private val ringNotifier: RingNotifier,
    private val onRing: () -> Unit = {},
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        val player = alarmPlayer()
        player.restoreStaleVolume()
        coroutineScope {
            val controller =
                RingController(
                    RingHandler(player, policyAccess()),
                    session,
                    elapsedRealtimeSource,
                    ringNotifier,
                    this,
                )
            LiveRingController.current = controller
            try {
                session.receive(Channel.CHANNEL_STATUS).collect { envelope ->
                    when {
                        envelope.hasRing() -> if (controller.ring()) onRing()
                        envelope.hasRingStop() -> controller.ringStopReceived()
                    }
                }
            } finally {
                controller.ringStopReceived()
                if (LiveRingController.current === controller) LiveRingController.current = null
            }
        }
    }
}
