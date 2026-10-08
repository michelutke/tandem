package dev.tandem.app.shell

import dev.tandem.core.pairing.DeviceInfoProvider
import dev.tandem.core.pairing.ManualNonceSource
import dev.tandem.core.pairing.ManualPairingAddress
import dev.tandem.core.pairing.ManualPairingConnector
import dev.tandem.core.pairing.ManualPairingStateMachine
import dev.tandem.core.pairing.PairingAttempt
import dev.tandem.core.pairing.PairingConnector
import dev.tandem.core.pairing.PairingState
import dev.tandem.core.pairing.PairingStateMachine
import dev.tandem.core.pairing.SecureRandomManualNonceSource
import dev.tandem.core.pairing.TrustCommitter
import dev.tandem.core.pairing.qr.PairingInvite
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Clock

/** What the pairing UI observes and drives (E20-26). */
interface PairingFlowControls {
    val state: StateFlow<PairingState>

    /** The owner tapped "Codes match". */
    fun confirmCodesMatch()

    /** The owner tapped "They don't match". Commits nothing. */
    fun cancel()

    /** Dismisses a finished or failed attempt, back to [PairingState.Idle]. */
    fun reset()
}

/** Not hosting a pairing flow: always [PairingState.Idle]. */
object NoPairingFlowControls : PairingFlowControls {
    override val state: StateFlow<PairingState> = MutableStateFlow(PairingState.Idle)

    override fun confirmCodesMatch() = Unit

    override fun cancel() = Unit

    override fun reset() = Unit
}

/**
 * Production [PairingStarter] (E20-26): one [PairingStateMachine] per scanned invite. Trust is
 * committed only by that machine, after `PairAccepted` and the owner's "Codes match"
 * (invariants 1, 3, 5, 6); this class adds no trust decision of its own and never logs the secret
 * or the confirmation code.
 */
class PairingFlow(
    private val clock: Clock,
    dispatcher: CoroutineDispatcher,
    private val connector: PairingConnector,
    private val trustCommitter: TrustCommitter,
    private val deviceInfoProvider: DeviceInfoProvider,
    private val manualConnector: ManualPairingConnector? = null,
    private val manualNonceSource: ManualNonceSource = SecureRandomManualNonceSource(),
) : PairingStarter,
    ManualPairingStarter,
    PairingFlowControls {
    private val machineDispatcher = dispatcher
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val mutableState = MutableStateFlow<PairingState>(PairingState.Idle)
    private var machine: PairingAttempt? = null
    private var forwarding: Job? = null

    override val state: StateFlow<PairingState> = mutableState.asStateFlow()

    override fun start(invite: PairingInvite) {
        run(PairingStateMachine(clock, machineDispatcher, connector, trustCommitter, invite, deviceInfoProvider))
    }

    /** No-op without a [manualConnector]; the manual machine commits trust only after the SAS is confirmed. */
    override fun startManual(address: ManualPairingAddress) {
        val manual = manualConnector ?: return
        run(ManualPairingStateMachine(clock, machineDispatcher, manual, trustCommitter, address, manualNonceSource))
    }

    private fun run(next: PairingAttempt) {
        discardMachine()
        machine = next
        forwarding = scope.launch { next.state.collect { mutableState.value = it } }
        next.start()
    }

    override fun confirmCodesMatch() {
        val current = machine ?: return
        scope.launch { current.confirmCodesMatch() }
    }

    override fun cancel() {
        machine?.cancelConfirm()
    }

    override fun reset() {
        discardMachine()
        mutableState.value = PairingState.Idle
    }

    private fun discardMachine() {
        forwarding?.cancel()
        forwarding = null
        machine?.close()
        machine = null
    }
}
