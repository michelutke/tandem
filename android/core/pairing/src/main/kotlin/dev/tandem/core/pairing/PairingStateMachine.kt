package dev.tandem.core.pairing

import dev.tandem.core.crypto.ConfirmationCode
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.qr.PairingInvite
import dev.tandem.core.pairing.qr.QrPairingPinSource
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.revoke
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.time.Clock
import kotlin.time.Duration.Companion.seconds

/**
 * Phone-side pairing state machine (E14-05; SPEC.md §2 "Pairing"; PairRequestBuilder E14-06,
 * QrPairingPinSource E14-04, TandemSession E12-11). [start] dials every [PairingInvite.addresses]
 * entry in order through the injected [PairingConnector] seam — never a real socket in this class
 * — with [CONNECT_TIMEOUT] per address (D-68); once connected it awaits `PairChallenge`, computes
 * and sends `PairRequest` (E14-06's [PairRequestBuilder]), then awaits `PairAccepted`/`PairRejected`
 * for up to [ACCEPT_TIMEOUT]. `PairAccepted` moves to [PairingState.AwaitingUserConfirm], armed
 * with its own [CONFIRM_TIMEOUT]; [confirmCodesMatch] and [cancelConfirm] are the owner's two
 * actions from there.
 *
 * [clock] and [dispatcher] are injected (E00-18) so every timeout here runs in virtual time under
 * `runTest` + `TestClock`: every timer, like [dev.tandem.core.protocol.connection.ConnectionStateMachine]'s,
 * is `delay`/`withTimeout`-based rather than reading [clock] directly, so it advances with whatever
 * dispatcher a test supplies; [clock] itself stamps the `pairedAt` this machine hands
 * [trustCommitter] on [PairingState.Paired].
 */
class PairingStateMachine(
    private val clock: Clock,
    dispatcher: CoroutineDispatcher,
    private val connector: PairingConnector,
    private val trustCommitter: TrustCommitter,
    private val invite: PairingInvite,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)

    private val mutableState = MutableStateFlow<PairingState>(PairingState.Idle)
    val state: StateFlow<PairingState> = mutableState.asStateFlow()

    private var confirmContext: ConfirmContext? = null
    private var confirmDeadline: Job? = null

    private class ConfirmContext(
        val session: TandemSession,
        val macFingerprint: SpkiFingerprint,
        val macName: String,
    )

    /** Idle -> Connecting; no-op if already started. */
    fun start() {
        if (mutableState.value != PairingState.Idle) return
        mutableState.value = PairingState.Connecting
        scope.launch { runPairing() }
    }

    /**
     * The owner tapped "Codes match" in [PairingState.AwaitingUserConfirm]: commits the Mac's
     * fingerprint via [trustCommitter] and moves to [PairingState.Paired]. No-op outside that state.
     */
    suspend fun confirmCodesMatch() {
        val context = confirmContext ?: return
        if (mutableState.value !is PairingState.AwaitingUserConfirm) return
        confirmContext = null
        confirmDeadline?.cancel()
        confirmDeadline = null
        trustCommitter.commit(context.macFingerprint, context.macName, clock.instant())
        mutableState.value = PairingState.Paired
    }

    /**
     * The owner tapped Cancel in [PairingState.AwaitingUserConfirm]: sends `Revoke`, closes the
     * session, and moves to [PairingState.Failed]`(`[PairingFailure.UserCancelled]`)`. No-op outside
     * that state.
     */
    fun cancelConfirm() {
        val context = confirmContext ?: return
        if (mutableState.value !is PairingState.AwaitingUserConfirm) return
        confirmContext = null
        scope.launch { declineConfirm(context.session, PairingFailure.UserCancelled) }
    }

    /** Callers own this machine's lifetime and MUST call this once done with it. */
    fun close() {
        scope.cancel()
    }

    private suspend fun runPairing() {
        val connection = dialAddresses() ?: return
        val session = connection.session
        mutableState.value = PairingState.AwaitingProofSent

        val challenge =
            waitForControlEnvelope(session) { it.payloadCase == Envelope.PayloadCase.PAIR_CHALLENGE }
        when (challenge) {
            is WaitOutcome.ConnectionLost -> mutableState.value = PairingState.Failed(PairingFailure.ConnectionLost)
            is WaitOutcome.Success -> sendPairRequestAndAwaitResult(connection, challenge.envelope)
        }
    }

    private suspend fun dialAddresses(): PairingConnection? {
        val pinSource = QrPairingPinSource(invite)
        for (address in invite.addresses) {
            val connection =
                try {
                    withTimeout(CONNECT_TIMEOUT) { connector.connect(address, invite.port, pinSource) }
                } catch (expectedAddressTimeout: TimeoutCancellationException) {
                    null
                }
            if (connection != null) return connection
        }
        mutableState.value = PairingState.Failed(PairingFailure.AllAddressesUnreachable)
        return null
    }

    private suspend fun sendPairRequestAndAwaitResult(
        connection: PairingConnection,
        challengeEnvelope: Envelope,
    ) {
        val session = connection.session
        val challenge = challengeEnvelope.pairChallenge.challenge.toByteArray()
        val request = PairRequestBuilder.build(invite, connection.macSpkiDer, connection.phoneSpkiDer, challenge)
        session.send(Channel.CHANNEL_CONTROL) { pairRequest = request }
        val code = ConfirmationCode.compute(invite.secret, connection.macSpkiDer, connection.phoneSpkiDer, challenge)
        mutableState.value = PairingState.AwaitingAccept(code)

        when (
            val outcome =
                withTimeoutOrNull(ACCEPT_TIMEOUT) {
                    waitForControlEnvelope(session) {
                        it.payloadCase == Envelope.PayloadCase.PAIR_ACCEPTED ||
                            it.payloadCase == Envelope.PayloadCase.PAIR_REJECTED
                    }
                }
        ) {
            null -> {
                mutableState.value = PairingState.Failed(PairingFailure.Timeout)
            }

            is WaitOutcome.ConnectionLost -> {
                mutableState.value = PairingState.Failed(PairingFailure.ConnectionLost)
            }

            is WaitOutcome.Success -> {
                val envelope = outcome.envelope
                if (envelope.payloadCase == Envelope.PayloadCase.PAIR_REJECTED) {
                    mutableState.value = PairingState.Rejected(envelope.pairRejected.reason)
                    session.close()
                } else {
                    confirmContext = ConfirmContext(session, SpkiFingerprint(invite.fingerprint), invite.macName)
                    mutableState.value = PairingState.AwaitingUserConfirm(code, invite.macName)
                    armConfirmDeadline()
                }
            }
        }
    }

    private fun armConfirmDeadline() {
        confirmDeadline =
            scope.launch {
                delay(CONFIRM_TIMEOUT)
                val context = confirmContext ?: return@launch
                confirmContext = null
                declineConfirm(context.session, PairingFailure.ConfirmationTimeout)
            }
    }

    private suspend fun declineConfirm(
        session: TandemSession,
        reason: PairingFailure,
    ) {
        confirmDeadline?.cancel()
        confirmDeadline = null
        runCatching { session.send(Channel.CHANNEL_CONTROL) { revoke = revoke {} } }
        session.close()
        mutableState.value = PairingState.Failed(reason)
    }

    private sealed class WaitOutcome {
        data class Success(
            val envelope: Envelope,
        ) : WaitOutcome()

        data object ConnectionLost : WaitOutcome()
    }

    /**
     * Races [predicate] matching a CONTROL-channel [Envelope] against [session]'s connection
     * dropping, cancelling whichever loses (E00-19-style seam, no real socket involved). A caller
     * wraps this in [withTimeoutOrNull] for the phases that have their own deadline.
     */
    private suspend fun waitForControlEnvelope(
        session: TandemSession,
        predicate: (Envelope) -> Boolean,
    ): WaitOutcome =
        coroutineScope {
            val received = async { session.receive(Channel.CHANNEL_CONTROL).first(predicate) }
            val disconnected = async { session.state.first { it is ConnectionState.Disconnected } }
            try {
                select {
                    received.onAwait { WaitOutcome.Success(it) }
                    disconnected.onAwait { WaitOutcome.ConnectionLost }
                }
            } finally {
                received.cancel()
                disconnected.cancel()
            }
        }

    companion object {
        /** SPEC.md §2 "Dialing the QR addresses (phone side)", D-68: 3 s per address. */
        val CONNECT_TIMEOUT = 3.seconds

        /** SPEC.md §2 "Frame order on a pairing-candidate connection", step 6: 120 s for the result. */
        val ACCEPT_TIMEOUT = 120.seconds

        /** SPEC.md §2 "Mutual confirmation": 120 s for the owner to tap "Codes match". */
        val CONFIRM_TIMEOUT = 120.seconds
    }
}
