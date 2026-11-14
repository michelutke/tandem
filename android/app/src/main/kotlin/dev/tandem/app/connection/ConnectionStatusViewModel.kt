package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionState
import kotlinx.coroutines.flow.StateFlow

/**
 * The connection state the Home screen shows (E20-09, E20-24; invariant 5, CLAUDE.md -- the
 * pin-mismatch [ConnectionState.Failed] case is the phone's only visible fail-closed surface) and the
 * paired Mac's display name. The status label itself is built by
 * [dev.tandem.app.home.HomeViewModel].
 */
class ConnectionStatusViewModel(
    val connectionState: StateFlow<ConnectionState>,
    val macName: StateFlow<String?>,
)
