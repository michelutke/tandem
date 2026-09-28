package dev.tandem.app.ring

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.tandem.app.di.AppDispatchers
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Receives the ring notification's "Stop" action tap (E23-06, F-4.4, UC-06). [RingNotification]
 * always sends [ACTION_STOP] as an explicit broadcast to this app's own component, so unlike
 * [dev.tandem.app.service.BootReceiver] no other action needs to be defended against.
 *
 * [ringControllerProvider] is an `internal var` (not a constructor parameter: `BroadcastReceiver`
 * is instantiated by the framework via a no-arg constructor), matching `BootReceiver`'s
 * `serviceStarterFactory` seam so tests can substitute a real [RingController] wired to a test
 * session before delivering [ACTION_STOP]. Nothing in production composes a live [RingController]
 * yet -- no composition root anywhere in `:app` owns a real, connected `TandemSession` (E12-11)
 * yet either; `TandemService`'s kdoc defers that to the E20-05+ reconnect issues -- so
 * [ringControllerProvider]'s production default resolves to nothing and [onReceive] no-ops; this
 * is the same known gap `RevokeHandler`/`UnpairAction` are in (flagged separately as E14-26/E20-21).
 */
class RingStopActionReceiver : BroadcastReceiver() {
    internal var ringControllerProvider: (Context) -> RingController? = { null }
    internal var dispatcher: CoroutineDispatcher = AppDispatchers.default

    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action != ACTION_STOP) return

        val ringController = ringControllerProvider(context) ?: return
        CoroutineScope(SupervisorJob() + dispatcher).launch { ringController.dismissedByPhone() }
    }

    companion object {
        const val ACTION_STOP = "dev.tandem.app.ring.ACTION_STOP"
    }
}
