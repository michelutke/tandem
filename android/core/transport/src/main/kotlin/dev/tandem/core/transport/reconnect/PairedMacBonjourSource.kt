package dev.tandem.core.transport.reconnect

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.discovery.DiscoveryEvent
import dev.tandem.core.discovery.PairedMacMatcher
import dev.tandem.core.discovery.ServiceDiscovery
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Production [BonjourCandidateSource] (E20-06): keeps a live snapshot of resolved `_tandem._tcp`
 * services whose advertised rotating id matches one of [pairedFingerprints] (E21-05's
 * [PairedMacMatcher]), by collecting [discovery]'s [ServiceDiscovery.browse] session for as long
 * as [start] has been called. A resolved service that stops matching -- or is reported lost -- is
 * dropped from the snapshot; recognition is a dial hint only (invariant 3, CLAUDE.md), never a
 * trust decision.
 */
class PairedMacBonjourSource(
    private val discovery: ServiceDiscovery,
    private val matcher: PairedMacMatcher,
    private val pairedFingerprints: () -> List<SpkiFingerprint>,
    dispatcher: CoroutineDispatcher,
) : BonjourCandidateSource {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val matched = linkedMapOf<String, CandidateAddress>()
    private var job: Job? = null

    /** Starts collecting [ServiceDiscovery.browse]. Idempotent: cancels and replaces any collection already running. */
    fun start() {
        job?.cancel()
        job =
            scope.launch {
                discovery.browse().collect { event ->
                    when (event) {
                        is DiscoveryEvent.Resolved -> {
                            val match = matcher.match(event.candidate, pairedFingerprints())
                            if (match != null) {
                                matched[event.candidate.serviceName] =
                                    CandidateAddress(event.candidate.host, event.candidate.port)
                            } else {
                                matched.remove(event.candidate.serviceName)
                            }
                        }

                        is DiscoveryEvent.Lost -> {
                            matched.remove(event.serviceName)
                        }

                        is DiscoveryEvent.Found -> {
                            // Not yet resolved: nothing to add to the snapshot.
                        }
                    }
                }
            }
    }

    /**
     * Stops collecting and cancels this instance's scope. Callers own this instance's lifetime
     * and MUST call this once done with it.
     */
    fun close() {
        scope.cancel()
    }

    override fun snapshot(): List<CandidateAddress> = matched.values.toList()
}
