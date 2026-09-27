package dev.tandem.core.discovery

import kotlinx.coroutines.flow.Flow

/**
 * Thin seam around `android.net.nsd.NsdManager`'s callback-based browse/resolve APIs (E21-04):
 * every retry, backoff and candidate-tracking decision lives in [NsdServiceDiscovery] against this
 * interface instead, so its unit tests substitute a scripted fake and never touch the framework.
 * [NsdManagerSource] is the only production implementation.
 */
interface NsdSource {
    /**
     * Starts browsing [serviceType]; emits every raw found/lost event until the returned [Flow]'s
     * collection is cancelled, which stops the underlying NsdManager discovery listener.
     */
    fun browse(serviceType: String): Flow<NsdBrowseEvent>

    /**
     * Resolves [service] to a host/port/TXT [ResolveOutcome]. API < 34 permits only one
     * outstanding `NsdManager.resolveService` call at a time system-wide; callers MUST serialize
     * calls to this function themselves ([NsdServiceDiscovery] does). A concurrent resolve fails
     * with `FAILURE_ALREADY_ACTIVE`, which the real implementation maps to a transient
     * [ResolveOutcome.Failure].
     */
    suspend fun resolve(service: NsdServiceRef): ResolveOutcome
}

/** Identifies one service instance across a browse session, independent of its resolved address. */
data class NsdServiceRef(
    val name: String,
    val serviceType: String,
)

/** A raw NsdManager discovery-listener callback, before any resolve is attempted. */
sealed interface NsdBrowseEvent {
    data class ServiceFound(
        val service: NsdServiceRef,
    ) : NsdBrowseEvent

    data class ServiceLost(
        val service: NsdServiceRef,
    ) : NsdBrowseEvent
}

/** The outcome of one [NsdSource.resolve] attempt. */
sealed interface ResolveOutcome {
    data class Success(
        val host: String,
        val port: Int,
        val txtRecords: Map<String, String>,
    ) : ResolveOutcome

    /** [transient] failures (e.g. `FAILURE_ALREADY_ACTIVE`) are worth retrying; others are not. */
    data class Failure(
        val transient: Boolean,
    ) : ResolveOutcome
}
