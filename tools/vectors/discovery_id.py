"""Generator for protocol/vectors/discovery-id.json (E01-20).

Covers `docs/protocol/SPEC.md` "Discovery TXT record" / "Rotating identifier" / "Skew
tolerance": `id = ` the first 8 bytes of `HMAC-SHA256(key = macSpkiFingerprint, message =
dayIndex as 8-byte big-endian)`, `dayIndex = floor(unixSecondsUTC / 86400)`.

Fixed SPKI fingerprint fixtures: real SPKI-fingerprint derivation (SHA-256 over a DER-encoded
P-256 SubjectPublicKeyInfo) is covered by the E01-17 `spki-fingerprint` category. Here the
fingerprint is only an opaque 32-byte HMAC key, so this module uses two documented, fixed
byte strings derived deterministically via SHA-256 over fixed ASCII labels instead of
generating or encoding real EC key material.
"""

from __future__ import annotations

import hashlib
import hmac
from datetime import datetime, timezone
from typing import Any

MAC_A_SPKI_FINGERPRINT_HEX = hashlib.sha256(b"tandem-vectors:mac-a-spki-der-placeholder").hexdigest()
MAC_B_SPKI_FINGERPRINT_HEX = hashlib.sha256(b"tandem-vectors:mac-b-spki-der-placeholder").hexdigest()


def _day_index(unix_seconds_utc: int) -> int:
    return unix_seconds_utc // 86400


def _compute_id_hex(spki_fingerprint_hex: str, day_index: int) -> str:
    message = day_index.to_bytes(8, "big", signed=False)
    digest = hmac.new(bytes.fromhex(spki_fingerprint_hex), message, hashlib.sha256).digest()
    return digest[:8].hex()


def _unix_seconds_utc(year: int, month: int, day: int, hour: int = 0, minute: int = 0, second: int = 0) -> int:
    return int(datetime(year, month, day, hour, minute, second, tzinfo=timezone.utc).timestamp())


def _compute_id_vector(vector_id: str, description: str, *, spki_fingerprint_hex: str, unix_seconds_utc: int) -> dict[str, Any]:
    day_index = _day_index(unix_seconds_utc)
    return {
        "id": vector_id,
        "description": description,
        "input": {
            "kind": "computeId",
            "macSpkiFingerprintHex": spki_fingerprint_hex,
            "unixSecondsUtc": unix_seconds_utc,
        },
        "expected": {
            "dayIndex": day_index,
            "idHex": _compute_id_hex(spki_fingerprint_hex, day_index),
        },
    }


def _recognition_vector(
    vector_id: str,
    description: str,
    *,
    receiver_unix_seconds_utc: int,
    paired_spki_fingerprint_hex: str,
    advertised_spki_fingerprint_hex: str,
    advertised_day_index: int,
) -> dict[str, Any]:
    receiver_day_index = _day_index(receiver_unix_seconds_utc)
    candidate_days = [receiver_day_index - 1, receiver_day_index, receiver_day_index + 1]
    candidate_ids_hex = [_compute_id_hex(paired_spki_fingerprint_hex, d) for d in candidate_days]
    advertised_id_hex = _compute_id_hex(advertised_spki_fingerprint_hex, advertised_day_index)

    entry: dict[str, Any] = {
        "id": vector_id,
        "description": description,
        "input": {
            "kind": "recognition",
            "pairedMacSpkiFingerprintHex": paired_spki_fingerprint_hex,
            "receiverUnixSecondsUtc": receiver_unix_seconds_utc,
            "advertisedSpkiFingerprintHex": advertised_spki_fingerprint_hex,
            "advertisedDayIndex": advertised_day_index,
        },
    }

    if advertised_id_hex in candidate_ids_hex:
        entry["expected"] = {
            "receiverDayIndex": receiver_day_index,
            "candidateIdsHex": candidate_ids_hex,
            "advertisedIdHex": advertised_id_hex,
            "recognized": True,
        }
    else:
        entry["expectedError"] = "notRecognized"

    return entry


def _txt_record_vector(vector_id: str, description: str, *, expected_error: str, **input_fields: Any) -> dict[str, Any]:
    return {
        "id": vector_id,
        "description": description,
        "input": {"kind": "txtRecord", **input_fields},
        "expectedError": expected_error,
    }


def generate_discovery_id_vectors() -> dict[str, Any]:
    recv_unix_seconds_utc = _unix_seconds_utc(2025, 1, 10, 8, 0, 0)
    receiver_day_index = _day_index(recv_unix_seconds_utc)
    valid_id_hex_at_receiver_day = _compute_id_hex(MAC_A_SPKI_FINGERPRINT_HEX, receiver_day_index)

    vectors = [
        _compute_id_vector(
            "discovery-id-epoch-day-0",
            "id for MAC A at dayIndex 0 (Unix epoch, 1970-01-01T00:00:00Z)",
            spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            unix_seconds_utc=0,
        ),
        _compute_id_vector(
            "discovery-id-epoch-day-1",
            "id for MAC A at dayIndex 1 (1970-01-02T00:00:00Z), rotated from dayIndex 0",
            spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            unix_seconds_utc=86400,
        ),
        _compute_id_vector(
            "discovery-id-future-day",
            "id for MAC A at an arbitrary far-future UTC instant (2030-03-15T12:00:00Z)",
            spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            unix_seconds_utc=_unix_seconds_utc(2030, 3, 15, 12, 0, 0),
        ),
        _compute_id_vector(
            "discovery-id-day-boundary-before-midnight",
            "id for MAC A one second before the UTC day boundary (2025-06-30T23:59:59Z)",
            spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            unix_seconds_utc=_unix_seconds_utc(2025, 6, 30, 23, 59, 59),
        ),
        _compute_id_vector(
            "discovery-id-day-boundary-at-midnight",
            "id for MAC A exactly at the following UTC day boundary (2025-07-01T00:00:00Z): "
            "dayIndex increments by exactly 1 from discovery-id-day-boundary-before-midnight "
            "and the id differs, catching local-timezone-instead-of-UTC bugs",
            spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            unix_seconds_utc=_unix_seconds_utc(2025, 7, 1, 0, 0, 0),
        ),
        _recognition_vector(
            "discovery-id-skew-minus-one-recognized",
            "advertised id computed at dayIndex-1 (yesterday) is within the receiver's +/-1 day "
            "skew window and MUST be recognized",
            receiver_unix_seconds_utc=recv_unix_seconds_utc,
            paired_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_day_index=receiver_day_index - 1,
        ),
        _recognition_vector(
            "discovery-id-skew-zero-recognized",
            "advertised id computed at the receiver's own dayIndex MUST be recognized",
            receiver_unix_seconds_utc=recv_unix_seconds_utc,
            paired_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_day_index=receiver_day_index,
        ),
        _recognition_vector(
            "discovery-id-skew-plus-one-recognized",
            "advertised id computed at dayIndex+1 (tomorrow) is within the receiver's +/-1 day "
            "skew window and MUST be recognized",
            receiver_unix_seconds_utc=recv_unix_seconds_utc,
            paired_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_day_index=receiver_day_index + 1,
        ),
        _recognition_vector(
            "discovery-id-skew-minus-two-not-recognized",
            "advertised id computed at dayIndex-2 is outside the +/-1 day skew window and MUST "
            "NOT be recognized",
            receiver_unix_seconds_utc=recv_unix_seconds_utc,
            paired_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_day_index=receiver_day_index - 2,
        ),
        _recognition_vector(
            "discovery-id-skew-plus-two-not-recognized",
            "advertised id computed at dayIndex+2 is outside the +/-1 day skew window and MUST "
            "NOT be recognized",
            receiver_unix_seconds_utc=recv_unix_seconds_utc,
            paired_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_day_index=receiver_day_index + 2,
        ),
        _recognition_vector(
            "discovery-id-other-mac-spki-not-recognized",
            "advertised id computed at the receiver's own dayIndex but with a different Mac's "
            "SPKI fingerprint (MAC B) MUST NOT be recognized against MAC A's candidates",
            receiver_unix_seconds_utc=recv_unix_seconds_utc,
            paired_spki_fingerprint_hex=MAC_A_SPKI_FINGERPRINT_HEX,
            advertised_spki_fingerprint_hex=MAC_B_SPKI_FINGERPRINT_HEX,
            advertised_day_index=receiver_day_index,
        ),
        _txt_record_vector(
            "discovery-txt-extra-key-malformed",
            "TXT record with an extra key beyond `v` and `id` MUST be treated as malformed and "
            "ignored",
            expected_error="malformedTxtRecord",
            v="1",
            idHex=valid_id_hex_at_receiver_day,
            extraKeys={"name": "Michel's MacBook Pro"},
        ),
        _txt_record_vector(
            "discovery-txt-id-too-short-malformed",
            "id of 7 bytes (14 lowercase hex characters, one short of the required 16) MUST be "
            "treated as malformed and ignored",
            expected_error="malformedTxtRecord",
            v="1",
            idHex=valid_id_hex_at_receiver_day[:14],
        ),
        _txt_record_vector(
            "discovery-txt-id-too-long-malformed",
            "id of 9 bytes (18 lowercase hex characters, one over the required 16) MUST be "
            "treated as malformed and ignored",
            expected_error="malformedTxtRecord",
            v="1",
            idHex=valid_id_hex_at_receiver_day + "ab",
        ),
        _txt_record_vector(
            "discovery-txt-id-non-hex-malformed",
            "id containing non-hexadecimal characters at the correct length MUST be treated as "
            "malformed and ignored",
            expected_error="malformedTxtRecord",
            v="1",
            idHex="gg" + valid_id_hex_at_receiver_day[2:],
        ),
        _txt_record_vector(
            "discovery-txt-missing-id-key-malformed",
            "TXT record missing the required `id` key entirely MUST be treated as malformed and "
            "ignored",
            expected_error="malformedTxtRecord",
            v="1",
        ),
        _txt_record_vector(
            "discovery-txt-unsupported-version",
            "TXT record with `v=2` MUST be ignored without raising an exception, since only "
            "`v=1` is recognized",
            expected_error="unsupportedVersion",
            v="2",
            idHex=valid_id_hex_at_receiver_day,
        ),
        _txt_record_vector(
            "discovery-txt-id-uppercase-not-recognized",
            "an advertised id that is an uppercase-hex re-encoding of a byte-for-byte-correct "
            "candidate id MUST NOT be canonicalized before comparison, so it is treated as "
            "non-matching, not as a match",
            expected_error="notRecognized",
            v="1",
            idHex=valid_id_hex_at_receiver_day.upper(),
            candidateIdHex=valid_id_hex_at_receiver_day,
        ),
    ]

    return {
        "$schema": "./schema.json",
        "category": "discovery-id",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
