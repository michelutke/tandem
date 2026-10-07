package dev.tandem.app.service

import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first

/**
 * Start decision for [TandemService] (E20-02, F-4.1): starts the foreground service only when a
 * paired Mac exists (trust store, E13-02), so the service -- and its mandatory ongoing
 * notification -- never appears before pairing. Framework-free (invokes [startForegroundService]
 * rather than touching `Context`/`Intent` itself) so it stays plain unit-tested (CLAUDE.md
 * Robolectric rule); [dev.tandem.app.TandemApplication] composes it with the real
 * [PairedPeerRepository] and `ContextCompat.startForegroundService`.
 */
class ServiceStarter(
    private val pairedPeerRepository: PairedPeerRepository,
    private val startForegroundService: () -> Unit,
) {
    suspend fun start() {
        if (pairedPeerRepository.observeHasPairedPeer().first()) {
            startForegroundService()
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
            .collect { startForegroundService() }
    }
}
