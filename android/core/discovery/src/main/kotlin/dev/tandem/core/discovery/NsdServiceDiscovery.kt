package dev.tandem.core.discovery

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

/**
 * Backoff schedule for [NsdServiceDiscovery]'s resolve retries (E21-04's "retrying transient
 * resolve failures with backoff"). Neither SPEC.md nor the backlog names concrete timings for
 * this — only that transient failures retry with backoff — so these are conservative engineering
 * defaults, not a protocol constant: [delays] holds the wait before each retry, so [maxAttempts]
 * (the initial attempt plus one retry per entry) is one more than [delays]' size.
 */
data class ResolveRetryPolicy(
    val delays: List<Duration> = listOf(250.milliseconds, 500.milliseconds),
) {
    val maxAttempts: Int = delays.size + 1
}

/**
 * [ServiceDiscovery] over an injected [NsdSource] (E21-04). Resolves are serialized through a
 * single worker coroutine reading [pendingResolves] — API < 34 permits only one outstanding
 * `NsdManager.resolveService` call at a time system-wide, and this module uses the same one
 * resolve-at-a-time path on every supported API level rather than branching on `Build.VERSION`
 * (one code path, matches D-67's rationale) — retrying a transient [ResolveOutcome.Failure] per
 * [retryPolicy] before giving up on that one service. Exhausting retries for one service never
 * cancels the browse session: later finds (including a re-find of the same service) still resolve.
 *
 * [dispatcher] is injected (seam rule, CLAUDE.md): every wait here is a plain `delay`, so a test
 * supplying a `TestDispatcher` advances backoff in virtual time.
 */
class NsdServiceDiscovery(
    private val source: NsdSource,
    private val dispatcher: CoroutineDispatcher,
    private val serviceType: String = SERVICE_TYPE,
    private val retryPolicy: ResolveRetryPolicy = ResolveRetryPolicy(),
) : ServiceDiscovery {
    override fun browse(): Flow<DiscoveryEvent> =
        channelFlow {
            val pendingResolves = Channel<NsdServiceRef>(Channel.UNLIMITED)
            launch {
                for (service in pendingResolves) {
                    resolveWithRetry(service)?.let { send(DiscoveryEvent.Resolved(it)) }
                }
            }
            try {
                source.browse(serviceType).collect { event ->
                    when (event) {
                        is NsdBrowseEvent.ServiceFound -> {
                            send(DiscoveryEvent.Found(event.service.name))
                            pendingResolves.send(event.service)
                        }

                        is NsdBrowseEvent.ServiceLost -> {
                            send(DiscoveryEvent.Lost(event.service.name))
                        }
                    }
                }
            } finally {
                pendingResolves.close()
            }
        }.flowOn(dispatcher)

    private suspend fun resolveWithRetry(service: NsdServiceRef): ResolvedService? {
        var attempt = 1
        while (true) {
            when (val outcome = source.resolve(service)) {
                is ResolveOutcome.Success -> {
                    return ResolvedService(service.name, outcome.host, outcome.port, outcome.txtRecords)
                }

                is ResolveOutcome.Failure -> {
                    if (!outcome.transient || attempt >= retryPolicy.maxAttempts) return null
                    delay(retryPolicy.delays[attempt - 1])
                    attempt++
                }
            }
        }
    }

    companion object {
        const val SERVICE_TYPE = "_tandem._tcp"
    }
}
