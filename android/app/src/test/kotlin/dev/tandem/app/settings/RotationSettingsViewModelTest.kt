package dev.tandem.app.settings

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// E70-06 tdd: initiator is a fake KeyRotator; no real key material is involved.
@OptIn(ExperimentalCoroutinesApi::class)
class RotationSettingsViewModelTest {
    private class FakeKeyRotator(
        private val result: KeyRotationResult,
    ) : KeyRotator {
        var calls = 0

        override suspend fun rotate(): KeyRotationResult {
            calls++
            return result
        }
    }

    private fun TestScope.viewModel(
        rotator: KeyRotator,
        authenticated: Boolean = true,
    ) = RotationSettingsViewModel(
        rotator = rotator,
        hasAuthenticatedSession = MutableStateFlow(authenticated),
        currentFingerprint = MutableStateFlow("A1B2 C3D4"),
        scope = TestScope(UnconfinedTestDispatcher(testScheduler)),
    )

    @Test
    fun rotationSettingsViewModel_noAuthenticatedSession_actionDisabled() =
        runTest {
            val rotator = FakeKeyRotator(KeyRotationResult.Success("E5F6 0718"))
            val viewModel = viewModel(rotator, authenticated = false)

            assertFalse(viewModel.actionEnabled.value)
            assertEquals("Connect to your Mac to rotate the key", viewModel.disabledReason.value)
            viewModel.requestRotation()
            assertEquals(RotationState.Idle, viewModel.state.value)
        }

    @Test
    fun rotationSettingsViewModel_userConfirms_reachesSuccessWithNewFingerprint() =
        runTest {
            val viewModel = viewModel(FakeKeyRotator(KeyRotationResult.Success("E5F6 0718")))

            assertTrue(viewModel.actionEnabled.value)
            viewModel.requestRotation()
            assertEquals(RotationState.Confirming, viewModel.state.value)
            viewModel.confirm()
            assertEquals(RotationState.Success("E5F6 0718"), viewModel.state.value)
        }

    @Test
    fun rotationSettingsViewModel_initiatorRejected_showsFailedAndOldFingerprint() =
        runTest {
            val viewModel = viewModel(FakeKeyRotator(KeyRotationResult.Failure("The Mac rejected the new key.")))

            viewModel.requestRotation()
            viewModel.confirm()

            assertEquals(RotationState.Failed("The Mac rejected the new key."), viewModel.state.value)
            assertEquals("A1B2 C3D4", viewModel.currentFingerprint.value)
        }

    @Test
    fun rotationSettingsViewModel_userCancels_initiatorNeverCalled() =
        runTest {
            val rotator = FakeKeyRotator(KeyRotationResult.Success("E5F6 0718"))
            val viewModel = viewModel(rotator)

            viewModel.requestRotation()
            viewModel.cancel()

            assertEquals(RotationState.Idle, viewModel.state.value)
            assertEquals(0, rotator.calls)
        }
}
