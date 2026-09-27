package dev.tandem.core.discovery

import kotlinx.coroutines.flow.Flow

/**
 * Bonjour/mDNS discovery of `_tandem._tcp` peers (E21-04; SPEC.md "Discovery TXT record",
 * invariant 4: mDNS runs in the system daemon, so browsing opens no listening socket in this app).
 * [browse] starts a browse session for as long as its returned [Flow] is collected — cancelling
 * collection stops discovery — and emits every service found, resolved or lost.
 *
 * Discovery is a hint only (SPEC.md "Discovery is a hint only", invariants 1 and 3): a
 * [DiscoveryEvent.Resolved] only ever supplies a candidate address. Matching a paired Mac's
 * rotating id (E21-05) and the mTLS pin check on any resulting connection attempt (E20-06) are
 * both entirely independent of anything emitted here.
 */
interface ServiceDiscovery {
    fun browse(): Flow<DiscoveryEvent>
}

/** One event from an active [ServiceDiscovery.browse] session. */
sealed interface DiscoveryEvent {
    /** NsdManager reported [serviceName] as present; a resolve for it is already in flight. */
    data class Found(
        val serviceName: String,
    ) : DiscoveryEvent

    /** [candidate] resolved to a host, port and TXT records. */
    data class Resolved(
        val candidate: ResolvedService,
    ) : DiscoveryEvent

    /** [serviceName] is no longer advertised; any previously resolved candidate for it is stale. */
    data class Lost(
        val serviceName: String,
    ) : DiscoveryEvent
}

/**
 * A resolved `_tandem._tcp` instance: an address candidate plus its raw, uninterpreted TXT map.
 * Interpreting [txtRecords] (the `v`/`id` keys, SPEC.md "Discovery TXT record") is E21-05's job,
 * not this module's.
 */
data class ResolvedService(
    val serviceName: String,
    val host: String,
    val port: Int,
    val txtRecords: Map<String, String>,
)
