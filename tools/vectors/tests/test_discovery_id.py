"""pytest suite for protocol/vectors/discovery-id.json (E01-20 tdd entries).

Recomputes each vector's expected id independently, straight from `hmac`/`hashlib` and the
SPEC.md formula (`docs/protocol/SPEC.md` "Rotating identifier"), rather than by calling into
`discovery_id.py`'s helpers — so a typo or regression in the generator's own arithmetic would
still be caught here.
"""

from __future__ import annotations

import hashlib
import hmac
from typing import Any

import vector_schema

MANIFEST_PATH = vector_schema.VECTORS_DIR / "discovery-id.json"


def _load_manifest() -> dict[str, Any]:
    return vector_schema.load_manifest(MANIFEST_PATH)


def _vectors_by_id(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {v["id"]: v for v in manifest["vectors"]}


def _reference_id_hex(spki_fingerprint_hex: str, day_index: int) -> str:
    message = day_index.to_bytes(8, "big", signed=False)
    digest = hmac.new(bytes.fromhex(spki_fingerprint_hex), message, hashlib.sha256).digest()
    return digest[:8].hex()


def test_bonjourRotatingIdVector_knownSpkiAndDayIndex_matchesExpectedId():
    manifest = _load_manifest()
    compute_id_vectors = [v for v in manifest["vectors"] if v["input"]["kind"] == "computeId"]

    assert len(compute_id_vectors) >= 4

    for vector in compute_id_vectors:
        spki_fingerprint_hex = vector["input"]["macSpkiFingerprintHex"]
        unix_seconds_utc = vector["input"]["unixSecondsUtc"]
        expected_day_index = unix_seconds_utc // 86400

        assert vector["expected"]["dayIndex"] == expected_day_index
        assert vector["expected"]["idHex"] == _reference_id_hex(spki_fingerprint_hex, expected_day_index)
        assert len(vector["expected"]["idHex"]) == 16
        assert vector["expected"]["idHex"] == vector["expected"]["idHex"].lower()


def test_bonjourRotatingIdVector_utcDayBoundary_consecutiveDayIndicesDifferentIds():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)

    before = by_id["discovery-id-day-boundary-before-midnight"]
    after = by_id["discovery-id-day-boundary-at-midnight"]

    assert after["input"]["unixSecondsUtc"] - before["input"]["unixSecondsUtc"] == 1
    assert after["expected"]["dayIndex"] == before["expected"]["dayIndex"] + 1
    assert after["expected"]["idHex"] != before["expected"]["idHex"]


def test_bonjourRotatingIdVector_skewOfTwoDays_expectedNotRecognized():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)

    for vector_id in ("discovery-id-skew-minus-two-not-recognized", "discovery-id-skew-plus-two-not-recognized"):
        vector = by_id[vector_id]
        assert vector["expectedError"] == "notRecognized"
        assert "expected" not in vector

        receiver_day_index = vector["input"]["receiverUnixSecondsUtc"] // 86400
        candidate_days = {receiver_day_index - 1, receiver_day_index, receiver_day_index + 1}
        assert vector["input"]["advertisedDayIndex"] not in candidate_days

    for vector_id in (
        "discovery-id-skew-minus-one-recognized",
        "discovery-id-skew-zero-recognized",
        "discovery-id-skew-plus-one-recognized",
    ):
        vector = by_id[vector_id]
        assert vector["expected"]["recognized"] is True
        assert vector["expected"]["advertisedIdHex"] in vector["expected"]["candidateIdsHex"]


def test_bonjourRotatingIdVector_otherMacSpki_expectedNotRecognized():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)

    vector = by_id["discovery-id-other-mac-spki-not-recognized"]

    assert vector["expectedError"] == "notRecognized"
    assert vector["input"]["advertisedSpkiFingerprintHex"] != vector["input"]["pairedMacSpkiFingerprintHex"]

    receiver_day_index = vector["input"]["receiverUnixSecondsUtc"] // 86400
    paired_candidate_ids = {
        _reference_id_hex(vector["input"]["pairedMacSpkiFingerprintHex"], d)
        for d in (receiver_day_index - 1, receiver_day_index, receiver_day_index + 1)
    }
    advertised_id = _reference_id_hex(
        vector["input"]["advertisedSpkiFingerprintHex"], vector["input"]["advertisedDayIndex"]
    )
    assert advertised_id not in paired_candidate_ids


def test_bonjourTxtVector_extraKeyOrWrongIdLength_expectedErrorMalformedTxtRecord():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)

    extra_key = by_id["discovery-txt-extra-key-malformed"]
    too_short = by_id["discovery-txt-id-too-short-malformed"]
    too_long = by_id["discovery-txt-id-too-long-malformed"]

    assert extra_key["expectedError"] == "malformedTxtRecord"
    assert "extraKeys" in extra_key["input"]

    assert too_short["expectedError"] == "malformedTxtRecord"
    assert len(too_short["input"]["idHex"]) == 14

    assert too_long["expectedError"] == "malformedTxtRecord"
    assert len(too_long["input"]["idHex"]) == 18

    unsupported_version = by_id["discovery-txt-unsupported-version"]
    assert unsupported_version["expectedError"] == "unsupportedVersion"
    assert unsupported_version["input"]["v"] == "2"


def test_bonjourVectorManifest_committedFile_validatesAgainstSchema():
    manifest = _load_manifest()
    assert vector_schema.validate_manifest(manifest) == []
