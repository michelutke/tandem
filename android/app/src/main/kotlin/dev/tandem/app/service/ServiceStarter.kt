package dev.tandem.app.service

import android.app.ForegroundServiceStartNotAllowedException
import android.util.Log
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first

/**
 * Start decision for [TandemService] (E20-02, F-4.1): starts the foreground service only when a
 * paired Mac exists (trust store, E13-02), so the service -- and its mandatory ongoing
 * notification -- never appears before pairing. Invokes [startForegroundService] rather than
 * touching `Context`/`Intent` itself; [dev.tandem.app.TandemApplication] composes it with the real
 * [PairedPeerRepository] and `ContextCompat.startForegroundService`.
 */
class ServiceStarter(
    private val pairedPeerRepository: PairedPeerRepository,
    private val startForegroundService: () -> Unit,
) {
    suspend fun start() {
        if (pairedPeerRepository.observeHasPairedPeer().first()) {
            startForegroundServiceIfAllowed()
        }
    }

    /**
     * API 31+ refuses a foreground start from the background (no battery-optimisation exemption);
     * that refusal is dropped here, and [keepStarted] retries once the app is next in the foreground.
     */
    private fun startForegroundServiceIfAllowed() {
        try {
            startForegroundService()
        } catch (_: ForegroundServiceStartNotAllowedException) {
            Log.w(TAG, "Foreground start not allowed; retrying when the app is opened")
        }
    }

    /**
     * Starts the service each time a paired Mac appears (pairing just committed trust) and
     * suspends until cancelled. Collected from the foreground activity so API 33+ foreground
     * service start rules are met.
     */
    suspend fun keepStarted() {
        pairedPeerRepository
            .observeHasPairedPeer()
            .distinctUntilChanged()
            .filter { it }
            .collect { startForegroundServiceIfAllowed() }
    }

    private companion object {
        const val TAG = "ServiceStarter"
    }
}
