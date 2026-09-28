package dev.tandem.core.transport.reconnect

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Reconnect address-selection state machine (E20-06; SPEC.md F-3.4, UC-04). Callers start this
 * once the control connection is reported dead or disconnected -- in this codebase that is
 * already every transition of `dev.tandem.core.protocol.connection.ConnectionStateMachine`
 * (E12-08) into `ConnectionState.Disconnected`/`ConnectionState.Failed`; there is no separate
 * `PeerDead` event to invent or wait for.
 *
 * One cycle dials, in order, [ReconnectStrategy.lastWorking] (if any), then [bonjourSource]'s
 * current snapshot, then [pairingAddressSource]'s addresses, deduplicated by [CandidateAddress]
 * equality so the same host/port is only dialed once per cycle even if it appears in more than
 * one source. A cycle that exhausts every candidate without success waits
 * [ReconnectBackoff.delayFor] the current failure count before starting the next cycle; a
 * successful [Connector.connect] resets that count to zero and records the winning address as
 * [lastWorking].
 *
 * CRITICAL (invariant 3, CLAUDE.md): [connector] is the only thing that ever decides trust here.
 * [CandidateAddress]'s source -- previously working, Bonjour-recognized, or recorded at pairing --
 * is a dial hint only. [ConnectResult.PinMismatch] (e.g. a host now answering on the last-working
 * address with a different key) is treated exactly like [ConnectResult.Unreachable]: the strategy
 * moves on to the next candidate in the same cycle rather than granting the address itself any
 * trust.
 *
 * Mirrors `ConnectionStateMachine`'s seam: [dispatcher] is where the backoff `delay` runs, so it
 * advances in virtual time under `runTest` + `TestClock`/`StandardTestDispatcher` (E00-18).
 *
 * [initialLastWorking] seeds [lastWorking] before this instance has ever connected -- a caller
 * that persists the last-working address across process restarts supplies it here instead of
 * waiting for a fresh success.
 */
class ReconnectStrategy(
    private val connector: Connector,
    private val bonjourSource: BonjourCandidateSource,
    private val pairingAddressSource: PairingAddressSource,
    dispatcher: CoroutineDispatcher,
    initialLastWorking: CandidateAddress? = null,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var job: Job? = null

    private val mutableLastWorking = MutableStateFlow(initialLastWorking)

    /** The address the most recent successful [Connector.connect] used, if any. */
    val lastWorking: StateFlow<CandidateAddress?> = mutableLastWorking.asStateFlow()

    private var failedCycles = 0

    /** Starts the reconnect loop. Idempotent: cancels and replaces any loop already running. */
    fun start() {
        job?.cancel()
        job = scope.launch { loop() }
    }

    /**
     * Stops the reconnect loop without connecting. Callers own this instance's lifetime and MUST
     * call [close] once done with it.
     */
    fun stop() {
        job?.cancel()
        job = null
    }

    /** Stops the loop and cancels this instance's scope. */
    fun close() {
        scope.cancel()
    }

    private suspend fun loop() {
        while (true) {
            for (candidate in buildCycle()) {
                when (connector.connect(candidate)) {
                    ConnectResult.Connected -> {
                        failedCycles = 0
                        mutableLastWorking.value = candidate
                        return
                    }

                    ConnectResult.PinMismatch, ConnectResult.Unreachable -> {
                        // Not trusted (or unreachable): move on to the next candidate this cycle.
                    }
                }
            }
            delay(ReconnectBackoff.delayFor(failedCycles))
            failedCycles++
        }
    }

    /**
     * This cycle's dial order: last-working, then Bonjour-resolved, then pairing-time addresses,
     * with duplicates (by [CandidateAddress] equality) collapsed to their first occurrence.
     */
    fun buildCycle(): List<CandidateAddress> =
        buildList {
            mutableLastWorking.value?.let(::add)
            addAll(bonjourSource.snapshot())
            addAll(pairingAddressSource.addresses())
        }.distinct()
}
