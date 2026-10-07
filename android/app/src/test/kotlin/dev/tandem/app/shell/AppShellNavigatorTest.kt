package dev.tandem.app.shell

import app.cash.turbine.test
import dev.tandem.core.designsystem.components.FloatingToolbarItem
import dev.tandem.core.storage.trust.PeerRecord
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

// E20-25 tdd: unit tests for the shell's state-based navigation
class AppShellNavigatorTest {
    private val peers = MutableStateFlow<List<PeerRecord>>(emptyList())
    private val navigator = AppShellNavigator(peers)

    @Test
    fun route_noPairedPeer_isOnboarding() =
        runTest {
            navigator.route.test { assertEquals(ShellRoute.Onboarding, awaitItem()) }
        }

    @Test
    fun route_pairedPeer_isHome() =
        runTest {
            peers.value = listOf(PEER)

            navigator.route.test { assertEquals(ShellRoute.Home, awaitItem()) }
        }

    @Test
    fun route_settingsSelectedWhilePaired_isSettings() =
        runTest {
            peers.value = listOf(PEER)
            navigator.select(FloatingToolbarItem.Settings)

            navigator.route.test { assertEquals(ShellRoute.Settings, awaitItem()) }
        }

    @Test
    fun route_peerRemovedWhileOnSettings_returnsToOnboarding() =
        runTest {
            peers.value = listOf(PEER)
            navigator.select(FloatingToolbarItem.Settings)

            navigator.route.test {
                assertEquals(ShellRoute.Settings, awaitItem())
                peers.value = emptyList()
                assertEquals(ShellRoute.Onboarding, awaitItem())
            }
        }

    @Test
    fun route_notificationsSelectedWhilePaired_isNotifications() =
        runTest {
            peers.value = listOf(PEER)
            navigator.select(FloatingToolbarItem.Notifications)

            navigator.route.test { assertEquals(ShellRoute.Notifications, awaitItem()) }
        }

    @Test
    fun route_activitySelectedWhilePaired_isActivity() =
        runTest {
            peers.value = listOf(PEER)
            navigator.select(FloatingToolbarItem.Activity)

            navigator.route.test { assertEquals(ShellRoute.Activity, awaitItem()) }
        }

    @Test
    fun resetToHome_afterSettings_selectsHome() =
        runTest {
            peers.value = listOf(PEER)
            navigator.select(FloatingToolbarItem.Settings)
            navigator.resetToHome()

            navigator.route.test { assertEquals(ShellRoute.Home, awaitItem()) }
        }

    private companion object {
        val PEER =
            PeerRecord(
                deviceId = "mac-1",
                displayName = "MacBook Pro",
                spkiSha256Base64Url = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                pairedAtEpochMs = 0L,
                lastSeenEpochMs = 0L,
                capabilities = emptyList(),
            )
    }
}
