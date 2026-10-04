package dev.tandem.core.storage.rotation

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.ROTATION_CHALLENGE_LENGTH
import dev.tandem.core.crypto.RotationProof
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.crypto.SpkiFingerprintException
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.storage.trust.GRACE_PERIOD_MS
import dev.tandem.core.storage.trust.PENDING_MAX_AGE_MS
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.KeyRotation
import dev.tandem.protocol.v1.RotationRejectReason
import dev.tandem.protocol.v1.rotationAck
import dev.tandem.protocol.v1.rotationChallenge
import dev.tandem.protocol.v1.rotationReject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.security.SecureRandom
import java.time.Clock

/** Redacted `rotation_rejected` event (E70-04): the reason only, never key or signature bytes. */
fun interface RotationEventLog {
    fun rotationRejected(reason: RotationRejectReason)
}

/**
 * Receives `KeyRotation` on one control session (E70-04; SPEC.md #key-rotation, D-34, D-74).
 * Once the session is Ready it sends exactly one `RotationChallenge` (held as `cb`, consumed by the
 * first `KeyRotation` that reaches signature verification) and then runs the SPEC's ordered
 * receiver algorithm. The Android receiver's peer is always a Mac, so a valid rotation is stored as
 * a *pending* pin; [run] promotes it when a handshake presents it and purges grace pins per the
 * grace rule.
 *
 * [authenticatedPeerSpkiDer] is the SPKI of the certificate that authenticated this session's TLS
 * handshake (null when the peer is not pinned, e.g. a pairing candidate). Signatures are only ever
 * verified against it, never against a key named in the message.
 */
@Suppress("TooManyFunctions") // private steps of the SPEC #key-rotation ordered receiver algorithm.
class RotationReceiver(
    private val session: TandemSession,
    private val authenticatedPeerSpkiDer: ByteArray?,
    private val pins: RotationPinStore,
    private val clock: Clock,
    private val random: SecureRandom,
    private val eventLog: RotationEventLog,
) {
    private var challenge: ByteArray? = null

    /** Suspends for the life of the session; returns when its CONTROL receive flow completes. */
    suspend fun run() {
        session.state.first { it is ConnectionState.Ready }
        sendChallenge()
        val graceFingerprint = applyHandshakePinRules()
        try {
            session
                .receive(Channel.CHANNEL_CONTROL)
                .filter { it.hasKeyRotation() }
                .collect { handle(it.keyRotation) }
        } finally {
            graceFingerprint?.let { withContext(NonCancellable) { pins.clearGrace(it) } }
        }
    }

    private suspend fun sendChallenge() {
        val cb = ByteArray(ROTATION_CHALLENGE_LENGTH).also(random::nextBytes)
        challenge = cb
        session.send(Channel.CHANNEL_CONTROL) {
            rotationChallenge = rotationChallenge { challenge = ByteString.copyFrom(cb) }
        }
    }

    /**
     * Promotes a presented pending pin and purges the grace pin once the new key is in use.
     * Returns the primary pin to clear when this grace-authenticated session closes, if any.
     */
    private suspend fun applyHandshakePinRules(): SpkiFingerprint? {
        val peer = authenticatedPeerFingerprint()
        val resolved = peer?.let { pins.resolve(it, nowEpochMs()) }
        return when (resolved?.kind) {
            PinKind.PENDING -> {
                pins.promotePending(requireNotNull(peer), nowEpochMs() + GRACE_PERIOD_MS)
                null
            }

            PinKind.PRIMARY -> {
                if (resolved.record.graceSpkiSha256Base64Url != null) pins.clearGrace(requireNotNull(peer))
                null
            }

            PinKind.GRACE -> {
                fingerprintOf(resolved.record.spkiSha256Base64Url)
            }

            null -> {
                null
            }
        }
    }

    private suspend fun handle(message: KeyRotation) {
        val peer = authenticatedPeerFingerprint()
        val resolved = peer?.let { pins.resolve(it, nowEpochMs()) }
        val newSpkiDer = message.newSpkiDer.toByteArray()
        val newFingerprint = strictFingerprintOrNull(newSpkiDer)
        if (resolved != null && isIdempotentResend(resolved, newFingerprint)) {
            sendAck()
            return
        }
        val reason =
            when {
                resolved == null -> RotationRejectReason.ROTATION_REJECT_REASON_UNAUTHENTICATED_SESSION
                resolved.kind != PinKind.PRIMARY -> RotationRejectReason.ROTATION_REJECT_REASON_NOT_PRIMARY_PIN
                hasActivePending(resolved) -> RotationRejectReason.ROTATION_REJECT_REASON_ROTATION_UNAVAILABLE
                newFingerprint == null -> RotationRejectReason.ROTATION_REJECT_REASON_INVALID_SIGNATURE
                else -> verifyAndStore(requireNotNull(peer), newFingerprint, newSpkiDer, message)
            }
        if (reason == null) sendAck() else sendReject(reason)
    }

    private suspend fun verifyAndStore(
        peer: SpkiFingerprint,
        newFingerprint: SpkiFingerprint,
        newSpkiDer: ByteArray,
        message: KeyRotation,
    ): RotationRejectReason? {
        val cb = challenge
        challenge = null
        val verified =
            cb != null &&
                RotationProof.verify(
                    requireNotNull(authenticatedPeerSpkiDer),
                    newSpkiDer,
                    cb,
                    message.sigOldKey.toByteArray(),
                    message.sigNewKey.toByteArray(),
                )
        return when {
            !verified -> RotationRejectReason.ROTATION_REJECT_REASON_INVALID_SIGNATURE

            pins.isPrimaryOrGrace(
                newFingerprint,
                nowEpochMs(),
            ) -> RotationRejectReason.ROTATION_REJECT_REASON_DUPLICATE_KEY

            storePending(peer, newFingerprint) -> null

            else -> RotationRejectReason.ROTATION_REJECT_REASON_ROTATION_UNAVAILABLE
        }
    }

    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    private suspend fun storePending(
        peer: SpkiFingerprint,
        newFingerprint: SpkiFingerprint,
    ): Boolean =
        try {
            pins.setPending(peer, newFingerprint, nowEpochMs())
        } catch (e: CancellationException) {
            throw e
        } catch (e: RuntimeException) {
            false
        }

    private fun isIdempotentResend(
        resolved: ResolvedPin,
        newFingerprint: SpkiFingerprint?,
    ): Boolean {
        if (newFingerprint == null || resolved.kind == PinKind.PENDING) return false
        val record = resolved.record
        return newFingerprint.base64Url == record.spkiSha256Base64Url ||
            newFingerprint.base64Url == record.pendingSpkiSha256Base64Url
    }

    private fun hasActivePending(resolved: ResolvedPin): Boolean {
        val since = resolved.record.pendingSinceEpochMs ?: return false
        return resolved.record.pendingSpkiSha256Base64Url != null && since > nowEpochMs() - PENDING_MAX_AGE_MS
    }

    private suspend fun sendAck() = session.send(Channel.CHANNEL_CONTROL) { rotationAck = rotationAck {} }

    private suspend fun sendReject(reason: RotationRejectReason) {
        eventLog.rotationRejected(reason)
        session.send(Channel.CHANNEL_CONTROL) { rotationReject = rotationReject { this.reason = reason } }
    }

    private fun authenticatedPeerFingerprint(): SpkiFingerprint? =
        authenticatedPeerSpkiDer?.let(::strictFingerprintOrNull)

    @Suppress("SwallowedException")
    private fun strictFingerprintOrNull(spkiDer: ByteArray): SpkiFingerprint? =
        try {
            spkiFingerprint(spkiDer)
        } catch (e: SpkiFingerprintException) {
            null
        }

    private fun fingerprintOf(base64Url: String): SpkiFingerprint =
        SpkiFingerprint(
            java.util.Base64
                .getUrlDecoder()
                .decode(base64Url),
        )

    private fun nowEpochMs(): Long = clock.instant().toEpochMilli()
}
