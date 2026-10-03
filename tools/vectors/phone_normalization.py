"""Generator for protocol/vectors/phone-normalization.json (E51-06).

Raw-to-E.164 phone-number normalization cases with a default region per case, run against Android's
libphonenumber-backed `PhoneNormalizer` and macOS's PhoneNumberKit-backed `PhoneNumberNormalizer`
so SMS/call matching keys are identical on both platforms. The expected values follow
libphonenumber's `isValidNumber` + E.164 format; `expected.e164` is `null` for anything that is not
a valid number (invalid, short code, alphanumeric sender id). A `#` suffix is an extension and is
dropped from the E.164 form.
"""

from __future__ import annotations

from typing import Any


def _vector(
    vector_id: str,
    description: str,
    *,
    raw: str,
    region: str,
    e164: str | None,
) -> dict[str, Any]:
    return {
        "id": vector_id,
        "description": description,
        "input": {"raw": raw, "region": region},
        "expected": {"e164": e164},
    }


def generate_phone_normalization_vectors() -> dict[str, Any]:
    vectors = [
        _vector(
            "phone-ch-national-spaced",
            "Swiss mobile in national format with spaces.",
            raw="079 123 45 67",
            region="CH",
            e164="+41791234567",
        ),
        _vector(
            "phone-ch-national-compact",
            "Swiss mobile in national format without separators.",
            raw="0791234567",
            region="CH",
            e164="+41791234567",
        ),
        _vector(
            "phone-ch-international-plus",
            "Swiss mobile with '+' country prefix and spaces.",
            raw="+41 79 123 45 67",
            region="CH",
            e164="+41791234567",
        ),
        _vector(
            "phone-ch-international-double-zero",
            "Swiss mobile with the '00' international call prefix.",
            raw="0041791234567",
            region="CH",
            e164="+41791234567",
        ),
        _vector(
            "phone-ch-international-dashes",
            "Swiss mobile with '+' prefix and dash separators.",
            raw="+41-79-123-45-67",
            region="CH",
            e164="+41791234567",
        ),
        _vector(
            "phone-ch-international-dots",
            "Swiss mobile with '+' prefix and dot separators.",
            raw="+41.79.123.45.67",
            region="CH",
            e164="+41791234567",
        ),
        _vector(
            "phone-de-national-landline",
            "German landline in national format.",
            raw="030 1234567",
            region="DE",
            e164="+49301234567",
        ),
        _vector(
            "phone-us-national-parenthesized",
            "US number in national format with parentheses and a dash.",
            raw="(650) 253-0000",
            region="US",
            e164="+16502530000",
        ),
        _vector(
            "phone-us-international-plus",
            "US number with '+1' and dashes.",
            raw="+1 650-253-0000",
            region="US",
            e164="+16502530000",
        ),
        _vector(
            "phone-gb-national-landline",
            "UK landline in national format.",
            raw="020 7946 0958",
            region="GB",
            e164="+442079460958",
        ),
        _vector(
            "phone-fr-national-mobile",
            "French mobile in national format.",
            raw="06 12 34 56 78",
            region="FR",
            e164="+33612345678",
        ),
        _vector(
            "phone-international-ignores-default-region",
            "A '+' number keeps its own country code regardless of the default region.",
            raw="+1 650 253 0000",
            region="CH",
            e164="+16502530000",
        ),
        _vector(
            "phone-ch-with-extension",
            "A '#' extension is dropped from the E.164 form.",
            raw="+41 44 668 18 00 #123",
            region="CH",
            e164="+41446681800",
        ),
        _vector(
            "phone-empty-null",
            "The empty string is not a number.",
            raw="",
            region="CH",
            e164=None,
        ),
        _vector(
            "phone-whitespace-only-null",
            "Whitespace alone is not a number.",
            raw="   ",
            region="CH",
            e164=None,
        ),
        _vector(
            "phone-too-short-invalid-null",
            "Four digits is not a valid number in any region.",
            raw="1234",
            region="CH",
            e164=None,
        ),
        _vector(
            "phone-unassigned-country-code-null",
            "'+' followed by an unassigned country code is invalid.",
            raw="+999 123456",
            region="CH",
            e164=None,
        ),
        _vector(
            "phone-invalid-national-number-null",
            "A well-formed but unassigned Swiss national number is invalid.",
            raw="079 000",
            region="CH",
            e164=None,
        ),
        _vector(
            "phone-short-code-emergency-null",
            "A US emergency short code is not a dialable subscriber number.",
            raw="911",
            region="US",
            e164=None,
        ),
        _vector(
            "phone-short-code-sms-null",
            "A five-digit SMS short code is not a valid number.",
            raw="12345",
            region="US",
            e164=None,
        ),
        _vector(
            "phone-short-code-swiss-null",
            "A Swiss three-digit service short code is not a valid number.",
            raw="144",
            region="CH",
            e164=None,
        ),
        _vector(
            "phone-alphanumeric-sender-null",
            "An alphanumeric sender id has no E.164 form.",
            raw="Swisscom",
            region="CH",
            e164=None,
        ),
        _vector(
            "phone-alphanumeric-sender-with-dash-null",
            "An alphanumeric sender id containing a dash has no E.164 form.",
            raw="UBS-Alert",
            region="CH",
            e164=None,
        ),
        _vector(
            "phone-vanity-letters-null",
            "Vanity letters are not translated to digits; the string has no E.164 form.",
            raw="1-800-FLOWERS",
            region="US",
            e164=None,
        ),
    ]
    return {
        "$schema": "./schema.json",
        "category": "phone-normalization",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
