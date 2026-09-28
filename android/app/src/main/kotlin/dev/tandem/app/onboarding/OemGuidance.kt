package dev.tandem.app.onboarding

/** One OEM's extra manual steps for keeping Tandem unrestricted, rendered under the OEM heading. */
data class OemGuidanceEntry(
    val steps: List<String>,
)

/**
 * Static OEM guidance table (E20-04): a dedicated entry for Samsung, Xiaomi, OnePlus and Huawei --
 * the OEM skins with the most aggressive background-kill behavior (`docs/testing/device-matrix.md`)
 * -- and [GENERIC] for every other manufacturer. Whether following these steps actually works on
 * real hardware is the `manual:` gate (E00-23); this table only has to render the right static
 * text.
 */
object OemGuidance {
    val SAMSUNG =
        OemGuidanceEntry(
            steps =
                listOf(
                    "Open Settings > Battery and device care > Battery > Background usage limits.",
                    "Remove Tandem from \"Sleeping apps\" and \"Deep sleeping apps\".",
                    "Set Tandem's own battery page to \"Unrestricted\".",
                ),
        )

    val XIAOMI =
        OemGuidanceEntry(
            steps =
                listOf(
                    "Open Settings > Apps > Manage apps > Tandem > Battery saver and set it to \"No restrictions\".",
                    "Open Settings > Apps > Permissions > Autostart and enable Tandem.",
                ),
        )

    val ONEPLUS =
        OemGuidanceEntry(
            steps =
                listOf(
                    "Open Settings > Battery > Battery optimization, find Tandem and choose \"Don't optimize\".",
                    "Open Settings > Apps > Tandem > Battery and disable \"Advanced optimization\".",
                ),
        )

    val HUAWEI =
        OemGuidanceEntry(
            steps =
                listOf(
                    "Open Settings > Apps > Apps > Tandem > Battery > App launch and switch it to \"Manage manually\".",
                    "Enable \"Auto-launch\", \"Secondary launch\" and \"Run in background\" for Tandem.",
                ),
        )

    val GENERIC =
        OemGuidanceEntry(
            steps =
                listOf(
                    "Open Settings > Apps > Tandem > Battery and allow unrestricted battery usage.",
                ),
        )

    /** Looks up the dedicated entry for [manufacturer] (case-insensitive), or [GENERIC]. */
    fun forManufacturer(manufacturer: String): OemGuidanceEntry =
        when (manufacturer.trim().lowercase()) {
            "samsung" -> SAMSUNG
            "xiaomi" -> XIAOMI
            "oneplus" -> ONEPLUS
            "huawei" -> HUAWEI
            else -> GENERIC
        }
}
