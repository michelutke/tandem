package dev.tandem.core.designsystem.components

import androidx.compose.ui.graphics.vector.ImageVector
import dev.tandem.core.designsystem.TandemIcons

/** The home floating toolbar's destinations (ui-spec.md §5.2). */
enum class FloatingToolbarItem(
    val label: String,
    val icon: ImageVector,
) {
    Home("Home", TandemIcons.home),
    Notifications("Notifications", TandemIcons.notifications),
    Activity("Activity", TandemIcons.history),
    Settings("Settings", TandemIcons.settings),
}
