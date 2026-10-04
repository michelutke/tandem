package dev.tandem.app.settings

/** Live values shown by [SettingsScreen] (E20-19; ui-spec.md §7.2 "Settings"). */
data class SettingsState(
    val macName: String,
    val batteryRestricted: Boolean,
    val keyShortCode: String,
)

private const val KEY_SHORT_CODE_GROUP = 4

/** Eight leading characters of a fingerprint's base64url form as two upper-case groups of four. */
fun keyShortCode(spkiSha256Base64Url: String): String =
    spkiSha256Base64Url
        .take(KEY_SHORT_CODE_GROUP * 2)
        .uppercase()
        .chunked(KEY_SHORT_CODE_GROUP)
        .joinToString(" ")
