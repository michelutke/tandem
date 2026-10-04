package dev.tandem.app.di

import dev.tandem.app.connection.SessionFeature
import dev.tandem.app.settings.KeyRotationResult
import dev.tandem.app.settings.KeyRotator
import dev.tandem.app.settings.ROTATION_DISABLED_REASON
import dev.tandem.app.settings.asKeyRotator
import dev.tandem.app.settings.keyShortCode
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.pairing.rotation.NextRotationDueStore
import dev.tandem.core.pairing.rotation.PendingRotationHandshake
import dev.tandem.core.pairing.rotation.RotationInitiator
import dev.tandem.core.pairing.rotation.RotationKeys
import dev.tandem.core.pairing.rotation.RotationOutcome
import dev.tandem.core.pairing.rotation.RotationScheduler
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import java.time.Clock
import java.time.Duration

/**
 * Key rotation as composed for the app (E70-15): one [rotationLock] shared by the per-session
 * [RotationInitiator] (through [sessionFeature]), the [pendingHandshake] in the dial path, the
 * settings [keyRotator] and the scheduler, so a rotation is never concurrent with another or with a
 * reconnect. Rotation only runs on a Ready, pinned session; [authenticated] turns true once one is
 * attached and its initiator has received the Mac's challenge (it stays true for the session), so
 * the scheduler never rotates before it can. Never logs keys or fingerprints.
 */
class RotationComposition(
    private val keys: RotationKeys,
    val rotationLock: Mutex,
    private val pairingInProgress: () -> Boolean,
) {
    val pendingHandshake = PendingRotationHandshake(keys.keyStore, keys.activeAlias, rotationLock)

    private val currentInitiator = MutableStateFlow<RotationInitiator?>(null)
    private val authenticatedState = MutableStateFlow(false)
    private val fingerprintState = MutableStateFlow(computeFingerprint())

    val authenticated: StateFlow<Boolean> = authenticatedState.asStateFlow()

    /** Short code of the active identity key; follows every committed rotation. */
    val activeFingerprint: StateFlow<String> = fingerprintState.asStateFlow()

    val keyRotator: KeyRotator =
        KeyRotator {
            currentInitiator.value?.asKeyRotator(::refreshFingerprint)?.rotate()
                ?: KeyRotationResult.Failure(ROTATION_DISABLED_REASON)
        }

    fun sessionFeature() =
        SessionFeature { session, _, _ ->
            val initiator = RotationInitiator(session, keys, rotationLock, peerPinned = true, pairingInProgress)
            currentInitiator.value = initiator
            try {
                coroutineScope {
                    val challengeWatcher =
                        launch {
                            initiator.hasChallenge.first { it }
                            if (currentInitiator.value === initiator) authenticatedState.value = true
                        }
                    initiator.run()
                    challengeWatcher.cancel()
                }
            } finally {
                if (currentInitiator.value === initiator) publish(null)
            }
        }

    fun refreshFingerprint(): String = computeFingerprint().also { fingerprintState.value = it }

    /** Suspends for the life of its scope; [intervals] emits null while scheduled rotation is Off. */
    suspend fun runScheduler(
        clock: Clock,
        store: NextRotationDueStore,
        intervals: Flow<Duration?>,
    ) {
        intervals.collectLatest { interval ->
            if (interval != null) RotationScheduler(clock, interval, store, authenticated, ::rotate).run()
        }
    }

    private suspend fun rotate(): RotationOutcome {
        val outcome = currentInitiator.value?.rotate() ?: RotationOutcome.NotAuthenticated
        if (outcome == RotationOutcome.Committed) refreshFingerprint()
        return outcome
    }

    private fun publish(initiator: RotationInitiator?) {
        currentInitiator.value = initiator
        authenticatedState.value = initiator != null
    }

    private fun computeFingerprint(): String =
        keys.keyStore
            .get(keys.activeAlias.current)
            ?.let { keyShortCode(spkiFingerprint(it.publicKey.encoded).base64Url) }
            .orEmpty()
}
