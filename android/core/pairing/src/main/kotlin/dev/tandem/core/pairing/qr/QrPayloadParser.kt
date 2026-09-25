package dev.tandem.core.pairing.qr

import dev.tandem.core.protocol.DisplayStringKind
import dev.tandem.core.protocol.DisplayStringSanitizer

/**
 * Parses and validates a `tandem://pair` QR payload per SPEC.md §2 (E01-21's `pair-uri` ABNF
 * grammar), hand-parsed rather than via `android.net.Uri` so this module stays pure JVM and
 * testable off-device. Rejects any field missing, duplicated, mis-encoded, or out of the
 * range/grammar SPEC.md §2 states, matching `tools/vectors/qr_payload.py`'s reference parser and
 * error taxonomy exactly ([InviteError]). Per-field validation lives in [QrFieldValidation] and
 * [QrEncoding]; `a`'s literal-address rules live in [LiteralAddressValidator].
 */
object QrPayloadParser {
    private const val SCHEME = "tandem"
    private const val HOST = "pair"
    private const val SCHEME_SEPARATOR = "://"
    private val REQUIRED_FIELDS = listOf("v", "fp", "s", "a", "p", "n")

    fun parse(uri: String): ParseInviteResult {
        val schemeSeparatorIndex = uri.indexOf(SCHEME_SEPARATOR)
        val schemeValid = schemeSeparatorIndex >= 0 && uri.substring(0, schemeSeparatorIndex) == SCHEME
        return if (!schemeValid) {
            ParseInviteResult.Rejected(InviteError.InvalidScheme)
        } else {
            parseHost(uri.substring(schemeSeparatorIndex + SCHEME_SEPARATOR.length))
        }
    }

    private fun parseHost(remainder: String): ParseInviteResult {
        val queryStart = remainder.indexOf('?')
        val host = if (queryStart < 0) remainder else remainder.substring(0, queryStart)
        return if (host != HOST) {
            ParseInviteResult.Rejected(InviteError.InvalidHost)
        } else {
            parseQuery(if (queryStart < 0) "" else remainder.substring(queryStart + 1))
        }
    }

    private fun parseQuery(query: String): ParseInviteResult {
        val fields = linkedMapOf<String, String>()
        val duplicateError = collectFields(query, fields)
        return if (duplicateError != null) {
            ParseInviteResult.Rejected(duplicateError)
        } else {
            buildInvite(fields)
        }
    }

    /** Splits `key=value` pairs on `&`, first `=` only (an unmatched key gets value `""`). */
    private fun collectFields(
        query: String,
        into: MutableMap<String, String>,
    ): InviteError? {
        for (pair in query.split("&")) {
            val equalsIndex = pair.indexOf('=')
            val key = if (equalsIndex >= 0) pair.substring(0, equalsIndex) else pair
            val value = if (equalsIndex >= 0) pair.substring(equalsIndex + 1) else ""
            if (key in into) return InviteError.DuplicatedField(key)
            into[key] = value
        }
        return null
    }

    private fun buildInvite(fields: Map<String, String>): ParseInviteResult {
        val error = fieldsError(fields)
        return if (error != null) {
            ParseInviteResult.Rejected(error)
        } else {
            ParseInviteResult.Accepted(toInvite(fields))
        }
    }

    private fun fieldsError(fields: Map<String, String>): InviteError? =
        REQUIRED_FIELDS.firstOrNull { it !in fields }?.let(InviteError::MissingRequiredField)
            ?: QrFieldValidation.versionError(fields.getValue("v"))
            ?: QrFieldValidation.fingerprintError(fields.getValue("fp"))
            ?: QrFieldValidation.secretError(fields.getValue("s"))
            ?: QrFieldValidation.addressListError(fields.getValue("a"))
            ?: QrFieldValidation.portError(fields.getValue("p"))
            ?: QrFieldValidation.nameError(fields.getValue("n"))

    /** Builds the invite from already-validated [fields]; every decode below is known to succeed. */
    private fun toInvite(fields: Map<String, String>): PairingInvite {
        val fingerprint = QrEncoding.decodeBase64Url(fields.getValue("fp")) ?: error("fp already validated")
        val secret = QrEncoding.decodeBase64Url(fields.getValue("s")) ?: error("secret already validated")
        val port = QrFieldValidation.parsePort(fields.getValue("p")) ?: error("port already validated")
        val rawName = QrEncoding.percentDecode(fields.getValue("n"))
        return PairingInvite(
            fingerprint = fingerprint,
            secret = secret,
            addresses = fields.getValue("a").split(","),
            port = port,
            macName = DisplayStringSanitizer.sanitize(rawName, DisplayStringKind.NAME),
        )
    }
}
