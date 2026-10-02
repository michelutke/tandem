package dev.tandem.app.settings

/** Live values shown by [SettingsScreen] (E20-19; ui-spec.md §7.2 "Settings"). */
data class SettingsState(
    val macName: String,
    val batteryRestricted: Boolean,
    val keyShortCode: String,
)
