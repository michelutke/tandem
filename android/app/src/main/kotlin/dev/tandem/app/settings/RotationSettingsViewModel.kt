package dev.tandem.app.settings

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface RotationState {
    data object Idle : RotationState

    data object Confirming : RotationState

    data object InProgress : RotationState

    data class Success(
        val newFingerprint: String,
    ) : RotationState

    data class Failed(
        val reason: String,
    ) : RotationState
}

const val ROTATION_DISABLED_REASON = "Connect to your Mac to rotate the key"

/**
 * "Rotate this device's key" settings action (E70-06). Idle -> Confirming -> InProgress ->
 * Success / Failed; cancelling never calls [rotator]. [currentFingerprint] is the active key's
 * fingerprint and is left untouched on failure.
 */
class RotationSettingsViewModel(
    private val rotator: KeyRotator,
    hasAuthenticatedSession: StateFlow<Boolean>,
    val currentFingerprint: StateFlow<String>,
    private val scope: CoroutineScope,
) {
    private val mutableState = MutableStateFlow<RotationState>(RotationState.Idle)
    val state: StateFlow<RotationState> = mutableState.asStateFlow()

    val actionEnabled: StateFlow<Boolean> =
        combine(hasAuthenticatedSession, mutableState) { authenticated, state ->
            authenticated && state !is RotationState.InProgress
        }.stateIn(scope, SharingStarted.Eagerly, hasAuthenticatedSession.value)

    val disabledReason: StateFlow<String?> =
        hasAuthenticatedSession
            .map { authenticated -> ROTATION_DISABLED_REASON.takeUnless { authenticated } }
            .stateIn(
                scope,
                SharingStarted.Eagerly,
                ROTATION_DISABLED_REASON.takeUnless { hasAuthenticatedSession.value },
            )

    fun requestRotation() {
        if (actionEnabled.value && state.value !is RotationState.Confirming) {
            mutableState.value = RotationState.Confirming
        }
    }

    fun cancel() {
        if (mutableState.value == RotationState.Confirming) mutableState.value = RotationState.Idle
    }

    fun confirm() {
        if (mutableState.value != RotationState.Confirming) return
        mutableState.value = RotationState.InProgress
        scope.launch {
            mutableState.value =
                when (val result = rotator.rotate()) {
                    is KeyRotationResult.Success -> RotationState.Success(result.newFingerprint)
                    is KeyRotationResult.Failure -> RotationState.Failed(result.reason)
                }
        }
    }

    fun dismissResult() {
        val current = mutableState.value
        if (current is RotationState.Success || current is RotationState.Failed) mutableState.value = RotationState.Idle
    }
}
