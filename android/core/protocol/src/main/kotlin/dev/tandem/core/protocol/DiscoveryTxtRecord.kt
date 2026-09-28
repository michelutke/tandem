package dev.tandem.core.protocol

/** A `_tandem._tcp` Bonjour TXT record's `id` field is exactly this many hex characters (8 bytes). */
private const val ID_HEX_LENGTH = 16

/** SPEC.md "Discovery TXT record" only recognizes this `v` value. */
private const val SUPPORTED_VERSION = "1"

/**
 * Validates the wire shape of a `_tandem._tcp` Bonjour TXT record (E21-02/E21-05, SPEC.md
 * "Discovery TXT record") before any of its fields are trusted: exactly the two keys `v` and `id`,
 * `id` exactly 16 hex characters, `v` exactly `"1"`. This is a shape check only -- `id`'s case is
 * preserved verbatim in [Parsed], never normalized, since `DiscoveryRotatingId.recognize`
 * (`core/crypto`) treats case as significant.
 */
object DiscoveryTxtRecord {
    /** Thrown by [parse] before any field is trusted. */
    sealed class ValidationError(
        message: String,
    ) : Exception(message) {
        /** `fields` does not have exactly the keys `v`/`id`, or `id` is not 16 hex characters. */
        class MalformedTxtRecord :
            ValidationError("TXT record must have exactly keys v/id, id must be $ID_HEX_LENGTH hex chars")

        /** `fields["v"]` is not `"1"`. */
        class UnsupportedVersion : ValidationError("unsupported TXT record version")
    }

    data class Parsed(
        val version: String,
        val idHex: String,
    )

    /**
     * Throws [ValidationError.MalformedTxtRecord] unless [fields] has exactly the keys `v` and
     * `id`, and `id` is exactly [ID_HEX_LENGTH] hex digits (any case -- this check is shape-only,
     * not the separate case-sensitive recognition comparison). Only then throws
     * [ValidationError.UnsupportedVersion] unless `v` is `"1"`.
     */
    fun parse(fields: Map<String, String>): Parsed {
        val idHex = fields["id"]
        val idHexValid = idHex != null && idHex.length == ID_HEX_LENGTH && idHex.all { it.isHexDigit() }
        if (fields.keys != setOf("v", "id") || idHex == null || !idHexValid) {
            throw ValidationError.MalformedTxtRecord()
        }

        val version = fields.getValue("v")
        if (version != SUPPORTED_VERSION) {
            throw ValidationError.UnsupportedVersion()
        }

        return Parsed(version = version, idHex = idHex)
    }

    private fun Char.isHexDigit(): Boolean = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
}
