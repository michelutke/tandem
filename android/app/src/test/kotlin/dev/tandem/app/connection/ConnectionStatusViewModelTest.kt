package dev.tandem.app.connection

import app.cash.turbine.test
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Duration

// E20-09 tdd:
//   unit: connectionStatusViewModel_stateMachineTransition_uiStateUpdatedWithin1s
//   unit: connectionStatusViewModel_pinMismatchError_mapsToErrorWithReasonText
//   unit: connectionStatusViewModel_threeUnreachableBackoffCycles_showsNetworkIsolationHint
@OptIn(ExperimentalCoroutinesApi::class)
class ConnectionStatusViewModelTest {
    @Test
    fun connectionStatusViewModel_stateMachineTransition_uiStateUpdatedWithin1s() =
        runTest {
            val clock = TestClock(testScheduler)
            val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected())
            val viewModel =
                ConnectionStatusViewModel(
                    connectionState = connectionState,
                    failedCycles = MutableStateFlow(0),
                    macName = MutableStateFlow(null),
                )

            viewModel.statusText.test {
                assertEquals("Disconnected", awaitItem())

                val transitionAt = clock.instant()
                connectionState.value = ConnectionState.Connecting

                assertEquals("Connecting…", awaitItem())
                assertTrue(Duration.between(transitionAt, clock.instant()).toMillis() < 1_000)
            }
        }

    @Test
    fun connectionStatusViewModel_pinMismatchError_mapsToErrorWithReasonText() =
        runTest {
            val connectionState =
                MutableStateFlow<ConnectionState>(
                    ConnectionState.Failed(ConnectionFailure.HandshakeError("PIN_MISMATCH")),
                )
            val viewModel =
                ConnectionStatusViewModel(
                    connectionState = connectionState,
                    failedCycles = MutableStateFlow(0),
                    macName = MutableStateFlow(null),
                )

            viewModel.statusText.test {
                assertEquals(
                    "Error: The PIN doesn't match. This device is not trusted.",
                    awaitItem(),
                )
            }
        }

    @Test
    fun connectionStatusViewModel_threeUnreachableBackoffCycles_showsNetworkIsolationHint() =
        runTest {
            val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected())
            val failedCycles = MutableStateFlow(0)
            val viewModel =
                ConnectionStatusViewModel(
                    connectionState = connectionState,
                    failedCycles = failedCycles,
                    macName = MutableStateFlow(null),
                )

            viewModel.statusText.test {
                assertEquals("Disconnected", awaitItem())

                failedCycles.value = 3

                assertEquals(
                    "Can't reach your Mac. Make sure both devices are on the same Wi-Fi. Guest " +
                        "networks and hotspots often block devices from reaching each other.",
                    awaitItem(),
                )
            }
        }
}
