package dev.tandem.app.connection.feature

import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.feature.calls.CallActionHandler
import dev.tandem.feature.calls.CallDetector
import dev.tandem.feature.calls.CallGateway
import dev.tandem.feature.calls.CallPermissions
import dev.tandem.feature.calls.CallSubscriptions
import dev.tandem.feature.calls.CallTracker
import dev.tandem.feature.calls.PlaceCallHandler
import dev.tandem.feature.calls.TapToCallNotifier
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.time.Clock

/**
 * Mirrors the phone's calls to the Mac and runs its answer, decline, hang-up and place-call
 * commands while a session is attached (F-8.4). Call state exists only while attached: nothing is
 * sent or kept outside a live session. [normalize] maps a raw number to E.164, null when it cannot.
 */
@Suppress("LongParameterList") // one seam per call collaborator
class CallsFeature(
    private val gateway: CallGateway,
    private val permissions: CallPermissions,
    private val subscriptions: CallSubscriptions,
    private val notifier: TapToCallNotifier,
    private val normalize: (String) -> String?,
    private val clock: Clock,
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    private val ioDispatcher: CoroutineDispatcher,
    private val onCallEnded: (talkSeconds: Long?) -> Unit = {},
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        val tracker = CallTracker()
        val detector =
            CallDetector(gateway, permissions, session, tracker, normalize, clock, onEnded = onCallEnded)
        val actions = CallActionHandler(gateway, permissions, tracker, session, ioDispatcher)
        val placeCalls =
            PlaceCallHandler(
                gateway,
                permissions,
                subscriptions,
                notifier,
                session,
                elapsedRealtimeSource,
                ioDispatcher,
            )
        coroutineScope {
            launch { detector.run() }
            launch { actions.run() }
            launch { placeCalls.run() }
        }
    }
}
