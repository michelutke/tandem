package dev.tandem.app.shell

import dev.tandem.core.designsystem.components.FloatingToolbarItem
import dev.tandem.core.storage.trust.PeerRecord
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine

enum class ShellRoute { Onboarding, Home, Settings }

/**
 * State-based navigation for the app shell (E20-25): onboarding until [peers] (the trust store's
 * list) holds a paired Mac, then Home or Settings per the floating toolbar. Only Home and
 * Settings are hosted; other toolbar items are ignored until their screens are wired.
 */
class AppShellNavigator(
    peers: Flow<List<PeerRecord>>,
) {
    private val selectedTab = MutableStateFlow(FloatingToolbarItem.Home)

    val route: Flow<ShellRoute> =
        combine(peers, selectedTab) { paired, tab ->
            when {
                paired.isEmpty() -> ShellRoute.Onboarding
                tab == FloatingToolbarItem.Settings -> ShellRoute.Settings
                else -> ShellRoute.Home
            }
        }

    fun select(item: FloatingToolbarItem) {
        if (item == FloatingToolbarItem.Home || item == FloatingToolbarItem.Settings) selectedTab.value = item
    }

    fun resetToHome() {
        selectedTab.value = FloatingToolbarItem.Home
    }
}
