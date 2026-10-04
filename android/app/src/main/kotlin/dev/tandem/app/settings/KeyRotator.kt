package dev.tandem.app.settings

import dev.tandem.core.pairing.rotation.RotationInitiator
import dev.tandem.core.pairing.rotation.RotationOutcome

sealed interface KeyRotationResult {
    data class Success(
        val newFingerprint: String,
    ) : KeyRotationResult

    data class Failure(
        val reason: String,
    ) : KeyRotationResult
}

/** Seam between the rotation UI and the session's [RotationInitiator] (E70-06). */
fun interface KeyRotator {
    suspend fun rotate(): KeyRotationResult
}

/** Adapts [RotationInitiator.rotate]; [activeFingerprint] reads the committed key's fingerprint. */
fun RotationInitiator.asKeyRotator(activeFingerprint: () -> String): KeyRotator =
    KeyRotator {
        when (rotate()) {
            RotationOutcome.Committed -> {
                KeyRotationResult.Success(activeFingerprint())
            }

            RotationOutcome.NotAuthenticated, RotationOutcome.NoChallenge -> {
                KeyRotationResult.Failure("Connect to your Mac to rotate the key.")
            }

            RotationOutcome.TimedOut -> {
                KeyRotationResult.Failure("The Mac did not answer in time.")
            }

            RotationOutcome.SessionDropped -> {
                KeyRotationResult.Failure("The connection dropped before the Mac answered.")
            }

            is RotationOutcome.Rejected -> {
                KeyRotationResult.Failure("The Mac rejected the new key.")
            }
        }
    }
