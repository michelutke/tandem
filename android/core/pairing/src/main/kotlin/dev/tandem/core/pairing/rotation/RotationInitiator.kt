package dev.tandem.core.pairing.rotation

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.IdentityKeyProvider
import dev.tandem.core.crypto.IdentityKeyStore
import dev.tandem.core.crypto.KeyHandle
import dev.tandem.core.crypto.ROTATION_CHALLENGE_LENGTH
import dev.tandem.core.crypto.RotationProof
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.RotationRejectReason
import dev.tandem.protocol.v1.keyRotation
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import java.security.Signature

/** SPEC.md #key-rotation, Timeouts and scheduling: no Ack/Reject within 30 s fails the attempt. */
const val ROTATION_REPLY_TIMEOUT_MS = 30_000L

sealed interface RotationOutcome {
    /** The Mac acked; the new key is the active identity and the old key is deleted. */
    data object Committed : RotationOutcome

    /** Not a fully authenticated Ready session; nothing was sent. */
    data object NotAuthenticated : RotationOutcome

    /** The Mac's `RotationChallenge` has not arrived on this session; nothing was sent. */
    data object NoChallenge : RotationOutcome

    /** No reply in time; the old key stays active and the new key is kept for a re-send on a later session. */
    data object TimedOut : RotationOutcome

    /** The session ended before a reply; the old key stays active and the rotation stays pending. */
    data object SessionDropped : RotationOutcome

    /** The Mac rejected; trust is unchanged, the old key stays active and the new key is deleted. */
    data class Rejected(
        val reason: RotationRejectReason,
    ) : RotationOutcome
}

/** The identity-key collaborators a rotation reads and mutates. */
class RotationKeys(
    val keyStore: IdentityKeyStore,
    val keyProvider: IdentityKeyProvider,
    val activeAlias: ActiveIdentityAlias,
)

/**
 * Phone-initiated key rotation on one control session (E70-02; SPEC.md #key-rotation, D-67, D-74).
 * [run] holds the Mac's unsolicited `RotationChallenge` as `cb` and routes `RotationAck` /
 * `RotationReject`; [rotate] generates the new key, signs the transcript with the old (active) and
 * the new key and sends `KeyRotation`. The old key stays active until `RotationAck`.
 *
 * A re-send after a lost Ack happens on a later session: [rotate] reuses the new key still sitting
 * under [ActiveIdentityAlias.nextAlias], so the Mac (which already holds it) acks idempotently.
 * [rotationLock] is shared with [PendingRotationHandshake] so the two never mutate keys concurrently.
 * Never logs keys or signatures.
 */
class RotationInitiator(
    private val session: TandemSession,
    private val keys: RotationKeys,
    private val rotationLock: Mutex,
    private val peerPinned: Boolean,
    private val pairingInProgress: () -> Boolean,
) {
    private val keyStore = keys.keyStore
    private val keyProvider = keys.keyProvider
    private val activeAlias = keys.activeAlias

    @Volatile
    private var challenge: ByteArray? = null

    @Volatile
    private var pendingReply: CompletableDeferred<RotationOutcome>? = null

    /** Suspends for the life of the session; returns when its CONTROL receive flow completes. */
    suspend fun run() {
        try {
            session.receive(Channel.CHANNEL_CONTROL).collect { envelope ->
                when {
                    envelope.hasRotationChallenge() -> {
                        val cb = envelope.rotationChallenge.challenge.toByteArray()
                        if (cb.size == ROTATION_CHALLENGE_LENGTH) challenge = cb
                    }

                    envelope.hasRotationAck() -> {
                        pendingReply?.complete(RotationOutcome.Committed)
                    }

                    envelope.hasRotationReject() -> {
                        pendingReply?.complete(RotationOutcome.Rejected(envelope.rotationReject.reason))
                    }
                }
            }
        } finally {
            pendingReply?.complete(RotationOutcome.SessionDropped)
        }
    }

    suspend fun rotate(): RotationOutcome =
        rotationLock.withLock {
            val cb = challenge
            when {
                !isAuthenticated() -> RotationOutcome.NotAuthenticated
                cb == null -> RotationOutcome.NoChallenge
                else -> sendAndAwaitReply(cb)
            }
        }

    private fun isAuthenticated(): Boolean =
        session.state.value is ConnectionState.Ready && peerPinned && !pairingInProgress()

    private suspend fun sendAndAwaitReply(cb: ByteArray): RotationOutcome {
        val oldAlias = activeAlias.current
        val oldKey = requireNotNull(keyStore.get(oldAlias)) { "Active identity key \"$oldAlias\" is missing" }
        val newKey = keyProvider.getOrCreateIdentityKey(activeAlias.nextAlias())
        val oldSpki = oldKey.publicKey.encoded
        val newSpki = newKey.publicKey.encoded
        val transcript = RotationProof.transcript(oldSpki, newSpki, cb)
        val sigOld = oldKey.sign(transcript)
        val sigNew = newKey.sign(transcript)

        val reply = CompletableDeferred<RotationOutcome>()
        pendingReply = reply
        challenge = null
        val outcome =
            try {
                session.send(Channel.CHANNEL_CONTROL) {
                    keyRotation =
                        keyRotation {
                            newSpkiDer = ByteString.copyFrom(newSpki)
                            sigOldKey = ByteString.copyFrom(sigOld)
                            sigNewKey = ByteString.copyFrom(sigNew)
                        }
                }
                withTimeoutOrNull(ROTATION_REPLY_TIMEOUT_MS) { reply.await() } ?: RotationOutcome.TimedOut
            } finally {
                pendingReply = null
            }

        when (outcome) {
            RotationOutcome.Committed -> commit(oldAlias, newKey)
            is RotationOutcome.Rejected -> keyStore.delete(newKey.alias)
            else -> Unit
        }
        return outcome
    }

    private fun commit(
        oldAlias: String,
        newKey: KeyHandle,
    ) {
        activeAlias.activate(newKey.alias)
        keyStore.delete(oldAlias)
    }
}

private fun KeyHandle.sign(message: ByteArray): ByteArray =
    Signature.getInstance("SHA256withECDSA").run {
        initSign(privateKey)
        update(message)
        sign()
    }
