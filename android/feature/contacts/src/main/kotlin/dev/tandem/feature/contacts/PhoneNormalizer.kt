package dev.tandem.feature.contacts

import com.google.i18n.phonenumbers.NumberParseException
import com.google.i18n.phonenumbers.PhoneNumberUtil

/** A phone string as read from the device plus its E.164 form, `null` when it cannot be normalized. */
data class NormalizedPhone(
    val raw: String,
    val normalizedE164: String?,
)

/**
 * E51-03 wraps libphonenumber to normalize numbers to E.164 for exact address matching (SMS, calls).
 * Unparsable input, short codes and alphanumeric sender IDs keep the raw string with a `null`
 * [NormalizedPhone.normalizedE164]; [normalize] never throws.
 */
class PhoneNormalizer(
    private val regionSource: RegionSource,
    private val phoneNumberUtil: PhoneNumberUtil = PhoneNumberUtil.getInstance(),
) {
    fun normalize(raw: String): NormalizedPhone = NormalizedPhone(raw, toE164(raw))

    private fun toE164(raw: String): String? {
        if (raw.any(Char::isLetter)) return null
        return try {
            val number = phoneNumberUtil.parse(raw, regionSource.defaultRegion())
            if (phoneNumberUtil.isValidNumber(number)) {
                phoneNumberUtil.format(number, PhoneNumberUtil.PhoneNumberFormat.E164)
            } else {
                null
            }
        } catch (_: NumberParseException) {
            null
        }
    }
}
