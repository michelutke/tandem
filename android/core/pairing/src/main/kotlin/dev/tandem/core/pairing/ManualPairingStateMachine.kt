package dev.tandem.core.pairing

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.ManualPairingContext
import dev.tandem.core.crypto.ManualPairingSas
import dev.tandem.core.crypto.PairingProofException
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.commitment
import dev.tandem.protocol.v1.reveal
import dev.tandem.protocol.v1.revoke
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.security.cert.CertificateException
import java.time.Clock
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * Phone-side manual pairing state machine (E73-03; ADR-008, SPEC.md "Manual pairing"). Dials the
 * typed [address] through the injected [ManualPairingConnector], awaits `PairChallenge` (its `cb`
 * binds the transcript), then runs the only valid order: phone `Commitment`, Mac `Commitment`,
 * phone `Reveal`, Mac `Reveal`, Mac `ManualPairResult`. The phone never sends its `Reveal` before
 * the Mac's `Commitment` arrived, and verifies the Mac's `Reveal` against that `Commitment` in
 * constant time. Any missing, repeated, out-of-order or malformed message, or a mismatching
 * `Reveal`, closes the connection as [PairingFailure.ProtocolViolation] with nothing pinned.
 *
 * The Mac is pinned (via [trustCommitter]) only by [confirmCodesMatch], and only after both
 * `ManualPairResult` was received and the owner tapped "Codes match" on the same SAS. There is no
 * code path that compares a fingerprint or fingerprint prefix as a substitute for the SAS.
 */
@Suppress("TooManyFunctions") // one small step per protocol message plus the owner's actions
class ManualPairingStateMachine(
    private val clock: Clock,
    dispatcher: CoroutineDispatcher,
    private val connector: ManualPairingConnector,
    private val trustCommitter: TrustCommitter,
    private val address: ManualPairingAddress,
    private val nonceSource: ManualNonceSource,
) : PairingAttempt {
    private val macName = DEFAULT_MAC_NAME

    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val mutableState = MutableStateFlow<PairingState>(PairingState.Idle)
    override val state: StateFlow<PairingState> = mutableState.asStateFlow()

    /** Guards [confirmContext]/[confirmDeadline] so exactly one of confirm/cancel/deadline/close wins. */
    private val confirmMutex = Mutex()
    private var confirmContext: ConfirmContext? = null
    private var confirmDeadline: Job? = null

    private class ConfirmContext(
        val session: TandemSession,
        val macFingerprint: SpkiFingerprint,
        var macAccepted: Boolean = false,
    )

    private sealed class Incoming {
        class Message(
            val envelope: Envelope,
        ) : Incoming() {
            override fun toString(): String = "Message(envelope=<redacted>)"
        }

        data object Lost : Incoming()

        data object TimedOut : Incoming()
    }

    override fun start() {
        if (mutableState.value != PairingState.Idle) return
        mutableState.value = PairingState.Connecting
        scope.launch { runPairing() }
    }

    /** Commits the Mac's fingerprint only once `ManualPairResult` arrived (see [ConfirmContext.macAccepted]). */
    override suspend fun confirmCodesMatch() {
        val context = claimConfirmContext(requireMacAccepted = true) ?: return
        trustCommitter.commit(context.macFingerprint, macName, clock.instant())
        mutableState.value = PairingState.Paired
        context.session.close()
    }

    /** "Codes differ" or Cancel, allowed as soon as the SAS is visible: sends `Revoke`, closes, commits nothing. */
    override fun cancelConfirm() {
        scope.launch {
            val context = claimConfirmContext(requireMacAccepted = false) ?: return@launch
            decline(context.session, PairingFailure.UserCancelled)
        }
    }

    override fun close() {
        scope
            .launch {
                val context = claimConfirmContext(requireMacAccepted = false) ?: return@launch
                runCatching { context.session.send(Channel.CHANNEL_CONTROL) { revoke = revoke {} } }
                context.session.close()
            }.invokeOnCompletion { scope.cancel() }
    }

    private suspend fun claimConfirmContext(requireMacAccepted: Boolean): ConfirmContext? =
        confirmMutex.withLock {
            val context = confirmContext ?: return@withLock null
            if (requireMacAccepted && !context.macAccepted) return@withLock null
            confirmContext = null
            confirmDeadline?.cancel()
            confirmDeadline = null
            context
        }

    @Suppress("TooGenericExceptionCaught", "SwallowedException", "ReturnCount")
    private suspend fun runPairing() {
        val connection =
            try {
                withTimeout(PairingStateMachine.CONNECT_TIMEOUT) { connector.connect(address.host, address.port) }
            } catch (expectedConnectTimeout: TimeoutCancellationException) {
                null
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (keyFailure: CertificateException) {
                mutableState.value = PairingState.Failed(PairingFailure.IncompatibleMacKey)
                return
            } catch (identityFailure: IdentityUnavailableException) {
                mutableState.value = PairingState.Failed(PairingFailure.IdentityUnavailable)
                return
            } catch (connectFailure: Exception) {
                null
            }
        if (connection == null) {
            mutableState.value = PairingState.Failed(PairingFailure.AllAddressesUnreachable)
            return
        }
        val session = connection.session
        val inbox = KtChannel<Envelope>(KtChannel.UNLIMITED)
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            session.receive(Channel.CHANNEL_CONTROL).collect { inbox.trySend(it) }
        }
        scope.launch {
            session.state.first { it is ConnectionState.Disconnected }
            inbox.close()
        }
        mutableState.value = PairingState.AwaitingProofSent
        exchange(connection, inbox)
    }

    @Suppress("ReturnCount", "CyclomaticComplexMethod", "SwallowedException")
    private suspend fun exchange(
        connection: PairingConnection,
        inbox: KtChannel<Envelope>,
    ) {
        val session = connection.session
        val challenge =
            next(inbox, PairingStateMachine.CHALLENGE_TIMEOUT).let { incoming ->
                when {
                    incoming is Incoming.Message &&
                        incoming.envelope.payloadCase == Envelope.PayloadCase.PAIR_CHALLENGE -> {
                        incoming.envelope.pairChallenge.challenge
                            .toByteArray()
                    }

                    incoming == Incoming.TimedOut -> {
                        return fail(session, PairingFailure.ChallengeTimeout)
                    }

                    incoming == Incoming.Lost -> {
                        return fail(session, PairingFailure.ConnectionLost)
                    }

                    else -> {
                        return fail(session, PairingFailure.ProtocolViolation)
                    }
                }
            }
        val context = ManualPairingContext(connection.macSpkiDer, connection.phoneSpkiDer, challenge)
        val noncePhone = nonceSource.generateNonce()
        val phoneCommitment =
            try {
                ManualPairingSas.commitment(ManualPairingSas.Role.PHONE, noncePhone, context)
            } catch (malformed: PairingProofException) {
                return fail(session, PairingFailure.MalformedChallenge)
            }
        session.send(Channel.CHANNEL_CONTROL) {
            commitment = commitment { hash = ByteString.copyFrom(phoneCommitment) }
        }

        val macCommitment =
            when (val incoming = next(inbox, PairingStateMachine.ACCEPT_TIMEOUT)) {
                is Incoming.Message -> incoming.envelope.takeIf { it.payloadCase == Envelope.PayloadCase.COMMITMENT }
                else -> return failFor(session, incoming)
            }?.commitment?.hash?.toByteArray()
        if (macCommitment == null || macCommitment.size != ManualPairingSas.COMMITMENT_BYTES) {
            return fail(session, PairingFailure.ProtocolViolation)
        }
        session.send(Channel.CHANNEL_CONTROL) { reveal = reveal { nonce = ByteString.copyFrom(noncePhone) } }

        val nonceMac =
            when (val incoming = next(inbox, PairingStateMachine.ACCEPT_TIMEOUT)) {
                is Incoming.Message -> incoming.envelope.takeIf { it.payloadCase == Envelope.PayloadCase.REVEAL }
                else -> return failFor(session, incoming)
            }?.reveal?.nonce?.toByteArray()
        if (nonceMac == null ||
            !ManualPairingSas.verifyCommitment(macCommitment, ManualPairingSas.Role.MAC, nonceMac, context)
        ) {
            return fail(session, PairingFailure.ProtocolViolation)
        }
        val sas = ManualPairingSas.sas(noncePhone, nonceMac, context)
        awaitMacResult(connection, inbox, sas)
    }

    private suspend fun awaitMacResult(
        connection: PairingConnection,
        inbox: KtChannel<Envelope>,
        sas: String,
    ) {
        val session = connection.session
        val macFingerprint = spkiFingerprint(connection.macSpkiDer)
        val context = ConfirmContext(session, macFingerprint)
        confirmMutex.withLock { confirmContext = context }
        mutableState.value = PairingState.ComparingCodes(sas)

        val incoming = next(inbox, PairingStateMachine.ACCEPT_TIMEOUT)
        val accepted =
            incoming is Incoming.Message &&
                incoming.envelope.payloadCase == Envelope.PayloadCase.MANUAL_PAIR_RESULT &&
                incoming.envelope.manualPairResult.accepted
        confirmMutex.withLock {
            if (confirmContext !== context) return
            if (accepted) {
                context.macAccepted = true
                mutableState.value = PairingState.AwaitingUserConfirm(sas, macName, manual = true)
                confirmDeadline =
                    scope.launch {
                        delay(PairingStateMachine.CONFIRM_TIMEOUT)
                        val expired = claimConfirmContext(requireMacAccepted = false) ?: return@launch
                        decline(expired.session, PairingFailure.ConfirmationTimeout)
                    }
                return
            }
            confirmContext = null
        }
        session.close()
        mutableState.value =
            when {
                incoming is Incoming.Message &&
                    incoming.envelope.payloadCase == Envelope.PayloadCase.PAIR_REJECTED -> {
                    PairingState.Rejected(incoming.envelope.pairRejected.reason)
                }

                incoming == Incoming.Lost -> {
                    PairingState.Failed(PairingFailure.ConnectionLost)
                }

                incoming == Incoming.TimedOut -> {
                    PairingState.Failed(PairingFailure.Timeout)
                }

                else -> {
                    PairingState.Failed(PairingFailure.ProtocolViolation)
                }
            }
    }

    /** The next CONTROL envelope that is not a `Heartbeat`, [Incoming.Lost] if the connection ended first. */
    private suspend fun next(
        inbox: KtChannel<Envelope>,
        timeout: kotlin.time.Duration,
    ): Incoming = withTimeoutOrNull(timeout) { receiveNonHeartbeat(inbox) } ?: Incoming.TimedOut

    private suspend fun receiveNonHeartbeat(inbox: KtChannel<Envelope>): Incoming {
        while (true) {
            val envelope = inbox.receiveCatching().getOrNull() ?: return Incoming.Lost
            if (envelope.payloadCase != Envelope.PayloadCase.HEARTBEAT) return Incoming.Message(envelope)
        }
    }

    private suspend fun failFor(
        session: TandemSession,
        incoming: Incoming,
    ) = fail(
        session,
        if (incoming == Incoming.TimedOut) PairingFailure.Timeout else PairingFailure.ConnectionLost,
    )

    private fun fail(
        session: TandemSession,
        reason: PairingFailure,
    ) {
        session.close()
        mutableState.value = PairingState.Failed(reason)
    }

    private suspend fun decline(
        session: TandemSession,
        reason: PairingFailure,
    ) {
        runCatching { session.send(Channel.CHANNEL_CONTROL) { revoke = revoke {} } }
        session.close()
        mutableState.value = PairingState.Failed(reason)
    }

    companion object {
        /** The Mac's name is not on the wire in manual pairing (no QR `n` field), so this is its label. */
        const val DEFAULT_MAC_NAME = "Mac"
    }
}
