package dev.tandem.app.home

import app.cash.turbine.test
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
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
        macName = MutableStateFlow("MacBook Pro"),
    )

    private fun blockedFor(failure: ConnectionFailure): BlockedReason? =
        runBlocking { viewModel(MutableStateFlow(ConnectionState.Failed(failure))).blocked.first() }

    @Test
    fun homeViewModel_pinMismatchFailure_blockedPinMismatch() =
        assertEquals(BlockedReason.PinMismatch, blockedFor(ConnectionFailure.HandshakeError("PIN_MISMATCH")))

    @Test
    fun homeViewModel_revokedFailure_blockedRevoked() =
        assertEquals(BlockedReason.Revoked, blockedFor(ConnectionFailure.HandshakeError("REVOKED")))

    @Test
    fun homeViewModel_versionMismatchFailure_blockedUpdateNeeded() =
        assertEquals(BlockedReason.UpdateNeeded, blockedFor(ConnectionFailure.VersionMismatch))

    @Test
    fun homeViewModel_timeoutFailure_notBlocked() = assertNull(blockedFor(ConnectionFailure.Timeout))

    @Test
    fun homeViewModel_otherHandshakeFailure_notBlocked() =
        assertNull(blockedFor(ConnectionFailure.HandshakeError("HANDSHAKE_FAILED")))

    @Test
    fun homeViewModel_readyState_notBlocked() =
        runTest {
            viewModel(MutableStateFlow(ConnectionState.Ready(Instant.EPOCH))).isBlocked.test {
                assertEquals(false, awaitItem())
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

    @Test
    fun homeViewModel_timeoutFailure_statusLineIsReconnecting() =
        runTest {
            val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Failed(ConnectionFailure.Timeout))
            viewModel(connectionState).statusLine.test {
                assertEquals("Reconnecting…", awaitItem())
            }
        }

    @Test
    fun homeViewModel_readyWhileSending_statusLineIsSending() =
        runTest {
            val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Ready(Instant.EPOCH))
            val ring = FakeHomeRingStateSource(HomeRingState.Transfer(percent = 43, toMac = true))
            viewModel(connectionState, ring).statusLine.test {
                assertEquals("Sending to Mac.", awaitItem())
            }
        }

    @Test
    fun homeViewModel_readyWhileReceiving_statusLineIsReceiving() =
        runTest {
            val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Ready(Instant.EPOCH))
            val ring = FakeHomeRingStateSource(HomeRingState.Transfer(percent = 43, toMac = false))
            viewModel(connectionState, ring).statusLine.test {
                assertEquals("Receiving from Mac.", awaitItem())
            }
        }
}
