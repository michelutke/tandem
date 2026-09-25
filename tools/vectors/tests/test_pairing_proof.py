"""pytest suite for protocol/vectors/pairing-proof.json (E01-18 tdd entries).

Every expectation here is recomputed independently with stdlib `hmac`/`hashlib` calls written
directly in this file (a from-scratch `LP`/transcript/HMAC implementation), never by importing
`pairing_proof.py`'s own generator functions -- so a bug shared between the generator and this
test would still be caught, matching `test_spki_fingerprint.py`'s openssl-cross-check approach.
"""

from __future__ import annotations

import hashlib
import hmac
from typing import Any

import vector_schema

MANIFEST_PATH = vector_schema.VECTORS_DIR / "pairing-proof.json"

PROOF_LABEL = b"tandem-pair-v1"
CODE_LABEL = b"tandem-pair-code-v1"


def _load_manifest() -> dict[str, Any]:
    return vector_schema.load_manifest(MANIFEST_PATH)


def _vectors_by_id(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {v["id"]: v for v in manifest["vectors"]}


def _lp(x: bytes) -> bytes:
    return len(x).to_bytes(2, "big") + x


def _recompute_proof(secret: bytes, mac_spki_der: bytes, phone_spki_der: bytes, cb: bytes) -> bytes:
    transcript = PROOF_LABEL + _lp(mac_spki_der) + _lp(phone_spki_der) + _lp(cb)
    return hmac.new(secret, transcript, hashlib.sha256).digest()


def _recompute_code(secret: bytes, mac_spki_der: bytes, phone_spki_der: bytes, cb: bytes) -> str:
    transcript = CODE_LABEL + _lp(mac_spki_der) + _lp(phone_spki_der) + _lp(cb)
    digest = hmac.new(secret, transcript, hashlib.sha256).digest()
    value = int.from_bytes(digest[:4], "big") % 1_000_000
    return f"{value:06d}"


def _verify(vector: dict[str, Any]) -> bool:
    """Independent from-scratch verifier: a `proofHex` is valid iff it is exactly 32 bytes and
    byte-equal to the recomputed HMAC-SHA256 over the correctly length-prefixed transcript."""
    input_ = vector["input"]
    mac_der = bytes.fromhex(input_["macSpkiDerHex"])
    phone_der = bytes.fromhex(input_["phoneSpkiDerHex"])
    if len(mac_der) != 91 or len(phone_der) != 91:
        raise ValueError("malformedSpki")
    secret = bytes.fromhex(input_["secretHex"])
    cb = bytes.fromhex(input_["cbHex"])
    proof = bytes.fromhex(input_["proofHex"])
    if len(proof) != 32:
        raise ValueError("malformedProof")
    expected_proof = _recompute_proof(secret, mac_der, phone_der, cb)
    return hmac.compare_digest(proof, expected_proof)


def test_pairingProofVector_correctInputs_matchesExpectedHmac():
    manifest = _load_manifest()
    positive_vectors = [
        v for v in manifest["vectors"] if v["input"]["kind"] == "proof" and "expected" in v
    ]

    assert len(positive_vectors) >= 5

    for vector in positive_vectors:
        assert vector["expected"] == {"valid": True}
        assert _verify(vector) is True


def test_pairingProofVector_wrongPhoneKey_expectedErrorProofMismatch():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["pairing-proof-wrong-phone-key"]

    assert vector["expectedError"] == "proofMismatch"
    assert _verify(vector) is False


def test_pairingProofVector_wrongSecret_expectedErrorProofMismatch():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["pairing-proof-wrong-secret"]

    assert vector["expectedError"] == "proofMismatch"
    assert _verify(vector) is False


def test_pairingProofVector_swappedSpkiOrder_expectedErrorProofMismatch():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["pairing-proof-swapped-spki-order"]

    assert vector["expectedError"] == "proofMismatch"
    assert _verify(vector) is False

    # Confirm this is actually a swapped-order proof, not some unrelated wrong value: HMAC over
    # the *swapped* transcript must equal the supplied proofHex.
    input_ = vector["input"]
    mac_der = bytes.fromhex(input_["macSpkiDerHex"])
    phone_der = bytes.fromhex(input_["phoneSpkiDerHex"])
    secret = bytes.fromhex(input_["secretHex"])
    cb = bytes.fromhex(input_["cbHex"])
    swapped_transcript = PROOF_LABEL + _lp(phone_der) + _lp(mac_der) + _lp(cb)
    swapped_proof = hmac.new(secret, swapped_transcript, hashlib.sha256).digest()
    assert bytes.fromhex(input_["proofHex"]) == swapped_proof


def test_pairingProofVector_proof31Bytes_expectedErrorMalformedProof():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["pairing-proof-31-byte-proof"]

    assert vector["expectedError"] == "malformedProof"
    assert len(bytes.fromhex(vector["input"]["proofHex"])) == 31
    try:
        _verify(vector)
        raised = False
    except ValueError as exc:
        raised = str(exc) == "malformedProof"
    assert raised


def test_pairingProofVector_rawConcatenationWithoutPrefixes_expectedErrorProofMismatch():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["pairing-proof-raw-concatenation-no-length-prefix"]

    assert vector["expectedError"] == "proofMismatch"
    assert _verify(vector) is False

    input_ = vector["input"]
    mac_der = bytes.fromhex(input_["macSpkiDerHex"])
    phone_der = bytes.fromhex(input_["phoneSpkiDerHex"])
    secret = bytes.fromhex(input_["secretHex"])
    cb = bytes.fromhex(input_["cbHex"])
    raw_transcript = PROOF_LABEL + mac_der + phone_der + cb
    raw_proof = hmac.new(secret, raw_transcript, hashlib.sha256).digest()
    assert bytes.fromhex(input_["proofHex"]) == raw_proof


def test_pairingProofVector_differentChannelBinding_expectedErrorProofMismatch():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["pairing-proof-different-channel-binding"]

    assert vector["expectedError"] == "proofMismatch"
    assert _verify(vector) is False


def test_pairingProofVector_rawPointInsteadOfSpkiDer_expectedErrorMalformedSpki():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["pairing-proof-raw-point-instead-of-spki-der"]

    phone_field = bytes.fromhex(vector["input"]["phoneSpkiDerHex"])
    assert len(phone_field) == 65
    assert phone_field[0] == 0x04
    assert vector["expectedError"] == "malformedSpki"
    try:
        _verify(vector)
        raised = False
    except ValueError as exc:
        raised = str(exc) == "malformedSpki"
    assert raised


def test_pairingProofVector_missingLabel_expectedErrorProofMismatch():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["pairing-proof-missing-label"]

    assert vector["expectedError"] == "proofMismatch"
    assert _verify(vector) is False

    input_ = vector["input"]
    mac_der = bytes.fromhex(input_["macSpkiDerHex"])
    phone_der = bytes.fromhex(input_["phoneSpkiDerHex"])
    secret = bytes.fromhex(input_["secretHex"])
    cb = bytes.fromhex(input_["cbHex"])
    no_label_transcript = _lp(mac_der) + _lp(phone_der) + _lp(cb)
    no_label_proof = hmac.new(secret, no_label_transcript, hashlib.sha256).digest()
    assert bytes.fromhex(input_["proofHex"]) == no_label_proof


def test_pairingCodeVector_leadingZeroCode_renderedAsSixDigits():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["pairing-code-leading-zero"]

    input_ = vector["input"]
    expected_code = _recompute_code(
        bytes.fromhex(input_["secretHex"]),
        bytes.fromhex(input_["macSpkiDerHex"]),
        bytes.fromhex(input_["phoneSpkiDerHex"]),
        bytes.fromhex(input_["cbHex"]),
    )

    assert vector["expected"]["code"] == expected_code
    assert len(expected_code) == 6
    assert expected_code.startswith("0")
    assert int(expected_code) < 100_000


def test_pairingCodeVector_differentChannelBinding_codeDiffers():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)
    baseline = by_id["pairing-code-fixture-a"]
    diff_cb = by_id["pairing-code-different-channel-binding"]

    assert baseline["input"]["secretHex"] == diff_cb["input"]["secretHex"]
    assert baseline["input"]["macSpkiDerHex"] == diff_cb["input"]["macSpkiDerHex"]
    assert baseline["input"]["phoneSpkiDerHex"] == diff_cb["input"]["phoneSpkiDerHex"]
    assert baseline["input"]["cbHex"] != diff_cb["input"]["cbHex"]
    assert baseline["expected"]["code"] != diff_cb["expected"]["code"]

    for vector in (baseline, diff_cb):
        input_ = vector["input"]
        expected_code = _recompute_code(
            bytes.fromhex(input_["secretHex"]),
            bytes.fromhex(input_["macSpkiDerHex"]),
            bytes.fromhex(input_["phoneSpkiDerHex"]),
            bytes.fromhex(input_["cbHex"]),
        )
        assert vector["expected"]["code"] == expected_code


def test_pairingCodeVector_sameChannelBindingDifferentMacSpki_codeDiffers():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)
    baseline = by_id["pairing-code-fixture-a"]
    relay = by_id["pairing-code-forwarded-challenge-relay"]

    assert baseline["input"]["secretHex"] == relay["input"]["secretHex"]
    assert baseline["input"]["cbHex"] == relay["input"]["cbHex"]
    assert baseline["input"]["phoneSpkiDerHex"] == relay["input"]["phoneSpkiDerHex"]
    assert baseline["input"]["macSpkiDerHex"] != relay["input"]["macSpkiDerHex"]
    assert baseline["expected"]["code"] != relay["expected"]["code"]

    for vector in (baseline, relay):
        input_ = vector["input"]
        expected_code = _recompute_code(
            bytes.fromhex(input_["secretHex"]),
            bytes.fromhex(input_["macSpkiDerHex"]),
            bytes.fromhex(input_["phoneSpkiDerHex"]),
            bytes.fromhex(input_["cbHex"]),
        )
        assert vector["expected"]["code"] == expected_code


def test_pairingProofVectorManifest_committedFile_validatesAgainstSchema():
    assert MANIFEST_PATH.exists(), f"missing committed manifest: {MANIFEST_PATH}"
    manifest = vector_schema.load_manifest(MANIFEST_PATH)
    assert vector_schema.validate_manifest(manifest) == []
    assert manifest["category"] == "pairing-proof"
