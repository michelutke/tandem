package dev.tandem.app.home

import app.cash.turbine.test
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

// E20-17 -- invariant 5, CLAUDE.md: the Blocked. trigger must match ConnectionErrorMapper's own
// PIN_MISMATCH/REVOKED cases exactly, not fire on plain network/timeout/version-mismatch failures.
@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelTest {
    private fun viewModel(
        connectionState: MutableStateFlow<ConnectionState> = MutableStateFlow(ConnectionState.Disconnected()),
        ringStateSource: HomeRingStateSource = FakeHomeRingStateSource(),
    ) = HomeViewModel(
        ringStateSource = ringStateSource,
        connectionState = connectionState,
        failedCycles = MutableStateFlow(0),
        macName = MutableStateFlow("MacBook Pro"),
    )

    @Test
    fun homeViewModel_pinMismatchFailure_isBlockedTrue() =
        runTest {
            val connectionState =
                MutableStateFlow<ConnectionState>(
                    ConnectionState.Failed(ConnectionFailure.HandshakeError("PIN_MISMATCH")),
                )
            viewModel(connectionState).isBlocked.test {
                assertTrue(awaitItem())
            }
        }

    @Test
    fun homeViewModel_revokedFailure_isBlockedTrue() =
        runTest {
            val connectionState =
                MutableStateFlow<ConnectionState>(
                    ConnectionState.Failed(ConnectionFailure.HandshakeError("REVOKED")),
                )
            viewModel(connectionState).isBlocked.test {
                assertTrue(awaitItem())
            }
        }

    @Test
    fun homeViewModel_versionMismatchFailure_isBlockedFalse() =
        runTest {
            val connectionState =
                MutableStateFlow<ConnectionState>(
                    ConnectionState.Failed(ConnectionFailure.HandshakeError("VERSION_MISMATCH")),
                )
            viewModel(connectionState).isBlocked.test {
                assertFalse(awaitItem())
            }
        }

    @Test
    fun homeViewModel_timeoutFailure_isBlockedFalse() =
        runTest {
            val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Failed(ConnectionFailure.Timeout))
            viewModel(connectionState).isBlocked.test {
                assertFalse(awaitItem())
            }
        }

    @Test
    fun homeViewModel_readyState_statusLineIsLinkedToMacName() =
        runTest {
            val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Ready(Instant.EPOCH))
            viewModel(connectionState).statusLine.test {
                assertEquals("Linked to MacBook Pro.", awaitItem())
            }
        }

    @Test
    fun homeViewModel_disconnectedState_statusLineIsReconnecting() =
        runTest {
            val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected())
            viewModel(connectionState).statusLine.test {
                assertEquals("Reconnecting…", awaitItem())
            }
        }
}
