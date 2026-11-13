package dev.tandem.app.settings

import java.util.Base64

/** Live values shown by [SettingsScreen] (E20-19; ui-spec.md §7.2 "Settings"). */
data class SettingsState(
    val macName: String,
    val batteryRestricted: Boolean,
    val keyShortCode: String,
    val connected: Boolean = true,
    val autoCapture: Boolean = false,
    val autoCaptureServiceOn: Boolean = false,
) {
    val connectionLabel: String get() = if (connected) "Connected" else "Not connected"
}

private const val KEY_SHORT_CODE_GROUP = 4
private const val KEY_SHORT_CODE_BYTES = 8

/** First eight bytes of the SPKI SHA-256 as 16 upper-case hex characters in four groups (ui-spec §3.2). */
fun keyShortCode(spkiSha256Base64Url: String): String =
    Base64
        .getUrlDecoder()
        .decode(spkiSha256Base64Url)
        .take(KEY_SHORT_CODE_BYTES)
        .joinToString("") { "%02X".format(it) }
        .chunked(KEY_SHORT_CODE_GROUP)
        .joinToString(" ")
