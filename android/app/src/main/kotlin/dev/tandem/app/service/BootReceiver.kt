package dev.tandem.app.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.tandem.app.TandemApplication
import dev.tandem.app.di.AppDispatchers
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Restarts [TandemService] after BOOT_COMPLETED (delivered after first unlock -- the app is not
 * direct-boot aware) and MY_PACKAGE_REPLACED (E20-08, F-4.1), so a paired Mac's connection resumes
 * without the user opening the app. Composes [ServiceStarter] the same way
 * [TandemApplication.onCreate] does: starts [TandemService] only when a paired Mac already exists
 * (E13-02 trust store), so the mandatory ongoing notification never appears before pairing.
 *
 * Exported (`tools/release-audit/android-exported.allowlist`, E00-28) so the system can deliver
 * BOOT_COMPLETED, but [onReceive] ignores any action other than BOOT_COMPLETED/MY_PACKAGE_REPLACED
 * as a defense-in-depth guard against an explicit intent another app could send straight at this
 * exported component, bypassing the manifest `<intent-filter>`'s action match.
 *
 * [serviceStarterFactory] and [dispatcher] are `internal var`s (not constructor parameters:
 * `BroadcastReceiver` is instantiated by the framework via a no-arg constructor) so tests can
 * substitute a fake repository and a `TestDispatcher`, matching [TandemService]'s seam.
 */
class BootReceiver : BroadcastReceiver() {
    internal var serviceStarterFactory: (Context) -> ServiceStarter = { context ->
        ServiceStarter(
            pairedPeerRepository =
                TrustStorePairedPeerRepository((context.applicationContext as TandemApplication).trustStore),
            startForegroundService = { context.startForegroundService(Intent(context, TandemService::class.java)) },
        )
    }
    internal var dispatcher: CoroutineDispatcher = AppDispatchers.default

    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }

        val serviceStarter = serviceStarterFactory(context)
        CoroutineScope(SupervisorJob() + dispatcher).launch { serviceStarter.start() }
    }
}
