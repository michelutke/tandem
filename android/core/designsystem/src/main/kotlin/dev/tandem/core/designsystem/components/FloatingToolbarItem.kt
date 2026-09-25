package dev.tandem.core.designsystem.components

/** The home floating toolbar's destinations (ui-spec.md §5.2). */
enum class FloatingToolbarItem(
    val label: String,
) {
    Home("Home"),
    Notifications("Notifications"),
    Activity("Activity"),
    Settings("Settings"),
}
