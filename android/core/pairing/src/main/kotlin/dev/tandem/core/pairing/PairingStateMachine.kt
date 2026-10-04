package dev.tandem.core.pairing

import dev.tandem.core.crypto.ConfirmationCode
import dev.tandem.core.crypto.PairingProofException
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.qr.PairingInvite
import dev.tandem.core.pairing.qr.QrPairingPinSource
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.revoke
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.security.cert.CertificateException
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
    private val deviceInfoProvider: DeviceInfoProvider,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)

    private val mutableState = MutableStateFlow<PairingState>(PairingState.Idle)
    val state: StateFlow<PairingState> = mutableState.asStateFlow()

    /** Guards [confirmContext]/[confirmDeadline] so exactly one of confirm/cancel/deadline/close wins. */
    private val confirmMutex = Mutex()
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
        val context = claimConfirmContext() ?: return
        trustCommitter.commit(context.macFingerprint, context.macName, clock.instant())
        mutableState.value = PairingState.Paired
        context.session.close()
    }

    /**
     * The owner tapped Cancel in [PairingState.AwaitingUserConfirm]: sends `Revoke`, closes the
     * session, and moves to [PairingState.Failed]`(`[PairingFailure.UserCancelled]`)`. No-op outside
     * that state.
     */
    fun cancelConfirm() {
        scope.launch {
            val context = claimConfirmContext() ?: return@launch
            declineConfirm(context.session, PairingFailure.UserCancelled)
        }
    }

    /**
     * Callers own this machine's lifetime and MUST call this once done with it. If a confirmation
     * is still pending, best-effort sends `Revoke` on that candidate connection before tearing this
     * machine's scope down (SPEC.md §2 "Mutual confirmation": the phone abandoning the dialog MUST
     * NOT leave the Mac's window open indefinitely).
     */
    fun close() {
        scope
            .launch {
                val context = claimConfirmContext() ?: return@launch
                runCatching { context.session.send(Channel.CHANNEL_CONTROL) { revoke = revoke {} } }
                context.session.close()
            }.invokeOnCompletion { scope.cancel() }
    }

    /**
     * Atomically claims [confirmContext] for whichever of [confirmCodesMatch]/[cancelConfirm]/the
     * [armConfirmDeadline] job/[close] calls it first, cancelling [confirmDeadline]; every later
     * caller (including the 120 s boundary racing a tap) gets `null` and no-ops (finding 5).
     */
    private suspend fun claimConfirmContext(): ConfirmContext? =
        confirmMutex.withLock {
            val context = confirmContext ?: return@withLock null
            confirmContext = null
            confirmDeadline?.cancel()
            confirmDeadline = null
            context
        }

    private suspend fun runPairing() {
        val connection = dialAddresses() ?: return
        val session = connection.session
        mutableState.value = PairingState.AwaitingProofSent

        val challenge =
            withTimeoutOrNull(CHALLENGE_TIMEOUT) {
                waitForControlEnvelope(session) { it.payloadCase == Envelope.PayloadCase.PAIR_CHALLENGE }
            }
        when (challenge) {
            null -> {
                session.close()
                mutableState.value = PairingState.Failed(PairingFailure.ChallengeTimeout)
            }

            is WaitOutcome.ConnectionLost -> {
                mutableState.value = PairingState.Failed(PairingFailure.ConnectionLost)
            }

            is WaitOutcome.Success -> {
                sendPairRequestAndAwaitResult(connection, challenge.envelope)
            }
        }
    }

    /**
     * Dials every address in order (D-68). A connect timeout advances to the next address; any
     * other connect/handshake failure (connection refused, TLS pin mismatch, hello version
     * mismatch, ...) does too, rather than crashing this machine's scope (finding 4) — only
     * exhausting every address is a terminal [PairingFailure.AllAddressesUnreachable], or
     * [PairingFailure.PinMismatch] if any address presented a key other than the QR fingerprint. The
     * [connector] seam is a `fun interface` with no declared throws, so any implementation's
     * connect/handshake failure surfaces as an unchecked exception of an unknown type; catching it
     * broadly here, rather than letting it escape to this machine's `SupervisorJob` uncaught, is
     * the fix, not an oversight.
     */
    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    private suspend fun dialAddresses(): PairingConnection? {
        val pinSource = QrPairingPinSource(invite)
        var pinMismatched = false
        for (address in invite.addresses) {
            val connection =
                try {
                    withTimeout(CONNECT_TIMEOUT) { connector.connect(address, invite.port, pinSource) }
                } catch (expectedAddressTimeout: TimeoutCancellationException) {
                    null
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (pinFailure: CertificateException) {
                    pinMismatched = true
                    null
                } catch (connectFailure: Exception) {
                    null
                }
            if (connection != null) return connection
        }
        val reason = if (pinMismatched) PairingFailure.PinMismatch else PairingFailure.AllAddressesUnreachable
        mutableState.value = PairingState.Failed(reason)
        return null
    }

    /**
     * The malformed-challenge branch below intentionally never rethrows or logs
     * [PairingProofException]: it maps straight to [PairingFailure.MalformedChallenge] with no
     * further detail exposed, so its message can't leak into a release log (invariant 7).
     */
    @Suppress("SwallowedException")
    private suspend fun sendPairRequestAndAwaitResult(
        connection: PairingConnection,
        challengeEnvelope: Envelope,
    ) {
        val session = connection.session
        val challenge = challengeEnvelope.pairChallenge.challenge.toByteArray()
        val requestAndCode =
            try {
                val request =
                    PairRequestBuilder.build(
                        invite,
                        connection.macSpkiDer,
                        connection.phoneSpkiDer,
                        challenge,
                        deviceInfoProvider,
                    )
                val code =
                    ConfirmationCode.compute(invite.secret, connection.macSpkiDer, connection.phoneSpkiDer, challenge)
                request to code
            } catch (malformed: PairingProofException) {
                session.close()
                mutableState.value = PairingState.Failed(PairingFailure.MalformedChallenge)
                return
            }
        val (request, code) = requestAndCode
        session.send(Channel.CHANNEL_CONTROL) { pairRequest = request }
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
                    confirmDeadline =
                        scope.launch {
                            delay(CONFIRM_TIMEOUT)
                            val context = claimConfirmContext() ?: return@launch
                            declineConfirm(context.session, PairingFailure.ConfirmationTimeout)
                        }
                }
            }
        }
    }

    private suspend fun declineConfirm(
        session: TandemSession,
        reason: PairingFailure,
    ) {
        runCatching { session.send(Channel.CHANNEL_CONTROL) { revoke = revoke {} } }
        session.close()
        mutableState.value = PairingState.Failed(reason)
    }

    private sealed class WaitOutcome {
        /** Plain, not `data`, class: default `toString()` must never print [envelope]'s bytes (finding 8). */
        class Success(
            val envelope: Envelope,
        ) : WaitOutcome() {
            override fun toString(): String = "Success(envelope=<redacted>)"
        }

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
            val received =
                async(start = CoroutineStart.UNDISPATCHED) { session.receive(Channel.CHANNEL_CONTROL).first(predicate) }
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

        /**
         * SPEC.md §10: the phone MUST reply with `PairRequest` within 10 s of the hello exchange
         * completing, and this single deadline covers the Mac's `PairChallenge` send too, so this
         * machine bounds its own wait for it the same way rather than relying solely on the Mac
         * closing the connection (finding 10).
         */
        val CHALLENGE_TIMEOUT = 10.seconds

        /** SPEC.md §2 "Frame order on a pairing-candidate connection", step 6: 120 s for the result. */
        val ACCEPT_TIMEOUT = 120.seconds

        /** SPEC.md §2 "Mutual confirmation": 120 s for the owner to tap "Codes match". */
        val CONFIRM_TIMEOUT = 120.seconds
    }
}
