"""pytest suite for protocol/vectors/spki-fingerprint.json (E01-17 tdd entries).

The positive vectors are cross-checked against an independent `openssl` reference pipeline
(`openssl pkey -pubin -outform DER | openssl dgst -sha256`), not against this repo's own
`hashlib.sha256` call in `spki_fingerprint.py`, so a bug shared between the generator and a
from-scratch fingerprint implementation would still be caught.
"""

from __future__ import annotations

import base64
import shutil
import subprocess
from typing import Any

import pytest
import vector_schema

MANIFEST_PATH = vector_schema.VECTORS_DIR / "spki-fingerprint.json"

OPENSSL_AVAILABLE = shutil.which("openssl") is not None


def _load_manifest() -> dict[str, Any]:
    return vector_schema.load_manifest(MANIFEST_PATH)


def _vectors_by_id(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {v["id"]: v for v in manifest["vectors"]}


def _der_to_pem(der: bytes) -> str:
    b64 = base64.encodebytes(der).decode("ascii")
    return f"-----BEGIN PUBLIC KEY-----\n{b64}-----END PUBLIC KEY-----\n"


def _openssl_sha256_fingerprint(der: bytes) -> str:
    pem = _der_to_pem(der)
    pkey = subprocess.run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input=pem.encode("ascii"),
        capture_output=True,
        check=True,
    )
    digest = subprocess.run(
        ["openssl", "dgst", "-sha256", "-r"],
        input=pkey.stdout,
        capture_output=True,
        check=True,
    )
    return digest.stdout.decode("ascii").split()[0]


@pytest.mark.skipif(not OPENSSL_AVAILABLE, reason="openssl binary not available")
def test_spkiFingerprintVector_knownP256Key_matchesOpensslReference():
    manifest = _load_manifest()
    positive_vectors = [v for v in manifest["vectors"] if "expected" in v]

    assert len(positive_vectors) >= 5

    for vector in positive_vectors:
        der = bytes.fromhex(vector["input"]["spkiDerHex"])
        assert len(der) == 91
        assert _openssl_sha256_fingerprint(der) == vector["expected"]["fingerprintHex"]
        assert vector["expected"]["fingerprintHex"] == vector["expected"]["fingerprintHex"].lower()


def test_spkiFingerprintVector_compressedPoint_expectedErrorUnsupportedPointEncoding():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["spki-fingerprint-compressed-point"]

    der = bytes.fromhex(vector["input"]["spkiDerHex"])
    # SEC1 compressed point prefix (0x02 even-y / 0x03 odd-y) where uncompressed requires 0x04.
    assert der[-33] in (0x02, 0x03)
    assert len(der) != 91
    assert vector["expectedError"] == "unsupportedPointEncoding"


def test_spkiFingerprintVector_p384Key_expectedErrorUnsupportedKeyType():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["spki-fingerprint-p384-curve"]

    der = bytes.fromhex(vector["input"]["spkiDerHex"])
    # secp384r1 OID 1.3.132.0.34 DER-encodes as 06 05 2B 81 04 00 22.
    assert bytes.fromhex("06052b81040022") in der
    assert vector["expectedError"] == "unsupportedKeyType"


def test_spkiFingerprintVector_rsaKey_expectedErrorUnsupportedKeyType():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["spki-fingerprint-rsa-2048"]

    der = bytes.fromhex(vector["input"]["spkiDerHex"])
    # rsaEncryption OID 1.2.840.113549.1.1.1 DER-encodes as 06 09 2A 86 48 86 F7 0D 01 01 01.
    assert bytes.fromhex("06092a864886f70d010101") in der
    assert vector["expectedError"] == "unsupportedKeyType"


def test_spkiFingerprintVector_truncatedDer_expectedErrorMalformedSpki():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["spki-fingerprint-truncated-der"]
    fixture_1 = _vectors_by_id(manifest)["spki-fingerprint-p256-fixture-1"]

    truncated_der = bytes.fromhex(vector["input"]["spkiDerHex"])
    full_der = bytes.fromhex(fixture_1["input"]["spkiDerHex"])

    assert truncated_der == full_der[:-1]
    assert len(truncated_der) == 90
    assert vector["expectedError"] == "malformedSpki"


def test_spkiVectorManifest_committedFile_validatesAgainstSchema():
    assert MANIFEST_PATH.exists(), f"missing committed manifest: {MANIFEST_PATH}"
    manifest = vector_schema.load_manifest(MANIFEST_PATH)
    assert vector_schema.validate_manifest(manifest) == []
    assert manifest["category"] == "spki-fingerprint"
