package dev.tandem.app.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.util.Log
import dev.tandem.app.R
import dev.tandem.app.TandemApplication
import dev.tandem.app.di.AppDispatchers
import dev.tandem.core.pairing.revoke.TrustRemover
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Foreground service (E20-02, F-4.1) with type `connectedDevice` (Android 14+ requirement --
 * SPEC.md's Doze/heartbeat expectations at #heartbeat assume this service is what keeps Tandem's
 * process alive with unrestricted battery). Owns the on-screen presence of the control-connection
 * lifecycle: shows the mandatory ongoing notification while started, and stops itself the moment
 * the last paired Mac is unpaired (UC-07). [ServiceStarter] (composed in
 * [dev.tandem.app.TandemApplication]) decides *whether* to start this service in the first place;
 * dialing/holding the actual control connection (E12-08 state machine, E12-11 session) is wired in
 * by the later reconnect issues (E20-05+) -- this issue owns only the Android service shell.
 *
 * [pairedPeerRepositoryFactory] and [dispatcher] are `internal var`s (not constructor parameters:
 * `Service` is instantiated by the framework via a no-arg constructor) so tests can substitute a
 * fake repository and a `TestDispatcher` before calling `onCreate()`, e.g. via
 * `Robolectric.buildService(TandemService::class.java).get()`. The default factory reads
 * [TandemApplication.trustStore] -- the one process-wide `TrustStore` instance -- rather than
 * opening its own connection to the trust store file: `TrustStore.observeList`'s reactivity comes
 * from Room's per-`RoomDatabase`-instance `InvalidationTracker`, so a second connection to the
 * same file would never see writes made through the first (e.g. an unpair action elsewhere in
 * `:app`), and this service would never stop.
 *
 * Also consumes the CONTROL channel of whichever session is registered in [sessionRegistry]
 * (E20-21): an incoming `Revoke` deletes that peer's trust record through [trustRemoverFactory]
 * and closes the session (AC-09), via the real `RevokeHandler`.
 */
class TandemService : Service() {
    internal var pairedPeerRepositoryFactory: (Context) -> PairedPeerRepository = { context ->
        TrustStorePairedPeerRepository((context.applicationContext as TandemApplication).trustStore)
    }
    internal var sessionRegistryFactory: (Context) -> SessionRegistry = { context ->
        (context.applicationContext as TandemApplication).sessionRegistry
    }
    internal var trustRemoverFactory: (Context) -> TrustRemover = { context ->
        val trustStore = (context.applicationContext as TandemApplication).trustStore
        TrustRemover { fingerprint -> trustStore.unpair(fingerprint) }
    }
    internal var dispatcher: CoroutineDispatcher = AppDispatchers.default

    private var job: Job? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)

        val pairedPeerRepository = pairedPeerRepositoryFactory(applicationContext)
        val sessionRegistry = sessionRegistryFactory(applicationContext)
        val trustRemover = trustRemoverFactory(applicationContext)
        val scope = CoroutineScope(SupervisorJob() + dispatcher + CoroutineExceptionHandler { _, e -> logFailure(e) })
        job = scope.coroutineContext[Job]
        scope.launch {
            pairedPeerRepository.observeHasPairedPeer().collectLatest { hasPairedPeer ->
                if (!hasPairedPeer) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }
        scope.launch {
            sessionRegistry.current.collectLatest { registered ->
                if (registered != null) consumeControlRevokeGuarded(registered, trustRemover)
            }
        }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int = START_STICKY

    @Suppress("TooGenericExceptionCaught") // a failing revoke must not end the consumer for later sessions
    private suspend fun consumeControlRevokeGuarded(
        registered: RegisteredSession,
        trustRemover: TrustRemover,
    ) {
        try {
            consumeControlRevoke(registered, trustRemover)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (e: Exception) {
            logFailure(e)
        }
    }

    private fun logFailure(e: Throwable) {
        Log.e(TAG, "Service task failed: ${e.javaClass.name}")
    }

    override fun onDestroy() {
        job?.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel =
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                getString(R.string.notification_connection_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        Notification
            .Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_connection_title))
            .setContentText(getString(R.string.notification_connection_text))
            .setSmallIcon(R.drawable.ic_notification_connection)
            .setOngoing(true)
            .build()

    companion object {
        const val NOTIFICATION_ID = 1
        const val NOTIFICATION_CHANNEL_ID = "connection_status"
        private const val TAG = "TandemService"
    }
}
