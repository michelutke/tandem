"""Generator for protocol/vectors/spki-fingerprint.json (E01-17).

Covers `docs/protocol/SPEC.md` "Certificate handling and the leaf-only check" / "Verify-callback
algorithm": the fingerprint of a peer's identity key is SHA-256 over the DER-encoded, uncompressed
P-256 `SubjectPublicKeyInfo` (exactly 91 bytes); anything else (a compressed point, a different
curve, a different key type, or truncated DER) MUST fail before any fingerprint comparison runs.

This module implements P-256 scalar multiplication and minimal ASN.1 DER encoding directly with
the standard library (`pow(x, -1, p)` modular inverse, `hashlib.shake_256` for a deterministic
"RSA-shaped" modulus) rather than depending on a third-party crypto library, matching the rest of
`tools/vectors`'s stdlib-only policy. It is not constant-time and MUST NOT be used outside this
generator / its tests.
"""

from __future__ import annotations

import hashlib
from typing import Any

# --- P-256 (secp256r1 / prime256v1) domain parameters (FIPS 186-4) ----------------------------

P256_P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
P256_A = P256_P - 3
P256_B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
P256_GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
P256_GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5
P256_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
P256_COORD_BYTES = 32

# secp384r1 (P-384), only used to build a wrong-curve negative fixture; no scalar math needed
# since a fabricated (not necessarily on-curve) point is enough to exercise curve-OID rejection.
P384_COORD_BYTES = 48

OID_EC_PUBLIC_KEY = "1.2.840.10045.2.1"
OID_PRIME256V1 = "1.2.840.10045.3.1.7"
OID_SECP384R1 = "1.3.132.0.34"
OID_RSA_ENCRYPTION = "1.2.840.113549.1.1.1"


def _inverse_mod(k: int, p: int) -> int:
    return pow(k, -1, p)


def _point_add(p1: tuple[int, int] | None, p2: tuple[int, int] | None) -> tuple[int, int] | None:
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    x1, y1 = p1
    x2, y2 = p2
    if x1 == x2 and (y1 + y2) % P256_P == 0:
        return None
    if p1 == p2:
        m = (3 * x1 * x1 + P256_A) * _inverse_mod(2 * y1, P256_P) % P256_P
    else:
        m = (y2 - y1) * _inverse_mod(x2 - x1, P256_P) % P256_P
    x3 = (m * m - x1 - x2) % P256_P
    y3 = (m * (x1 - x3) - y1) % P256_P
    return x3, y3


def _scalar_mult(k: int, point: tuple[int, int]) -> tuple[int, int]:
    result: tuple[int, int] | None = None
    addend = point
    while k:
        if k & 1:
            result = _point_add(result, addend)
        addend = _point_add(addend, addend)
        k >>= 1
    if result is None:
        raise ValueError("scalar multiple is the point at infinity")
    return result


def p256_public_point(private_scalar: int) -> tuple[int, int]:
    """Derives the P-256 public point for a fixed private scalar via double-and-add scalar
    multiplication of the base point. Not constant-time; test-vector generation only."""
    if not (1 <= private_scalar < P256_N):
        raise ValueError("private scalar out of [1, n) range")
    return _scalar_mult(private_scalar, (P256_GX, P256_GY))


def _fixed_scalar(label: str) -> int:
    """A deterministic, checked-in-by-construction private scalar derived from a fixed ASCII
    label, reduced into [1, n)."""
    digest = hashlib.sha256(f"tandem-vectors:spki-private-scalar:{label}".encode("ascii")).digest()
    return (int.from_bytes(digest, "big") % (P256_N - 1)) + 1


# --- minimal ASN.1 DER encoding ----------------------------------------------------------------


def _der_length(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    length_bytes = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(length_bytes)]) + length_bytes


def _der_tlv(tag: int, content: bytes) -> bytes:
    return bytes([tag]) + _der_length(len(content)) + content


def _der_oid(dotted: str) -> bytes:
    parts = [int(p) for p in dotted.split(".")]
    out = bytearray([parts[0] * 40 + parts[1]])
    for value in parts[2:]:
        if value == 0:
            out.append(0)
            continue
        chunk = []
        while value:
            chunk.append(value & 0x7F)
            value >>= 7
        chunk.reverse()
        for i, byte in enumerate(chunk):
            out.append(byte | 0x80 if i != len(chunk) - 1 else byte)
    return _der_tlv(0x06, bytes(out))


def _der_null() -> bytes:
    return _der_tlv(0x05, b"")


def _der_integer(value: int) -> bytes:
    if value == 0:
        content = b"\x00"
    else:
        length = (value.bit_length() + 7) // 8
        content = value.to_bytes(length, "big")
        if content[0] & 0x80:
            content = b"\x00" + content
    return _der_tlv(0x02, content)


def _der_bit_string(content_without_unused_bits_byte: bytes) -> bytes:
    return _der_tlv(0x03, b"\x00" + content_without_unused_bits_byte)


def _ec_point_uncompressed(x: int, y: int, coord_bytes: int) -> bytes:
    return b"\x04" + x.to_bytes(coord_bytes, "big") + y.to_bytes(coord_bytes, "big")


def _ec_point_compressed(x: int, y: int, coord_bytes: int) -> bytes:
    prefix = 0x02 if y % 2 == 0 else 0x03
    return bytes([prefix]) + x.to_bytes(coord_bytes, "big")


def build_ec_spki_der(*, curve_oid: str, point_bytes: bytes) -> bytes:
    algorithm = _der_tlv(0x30, _der_oid(OID_EC_PUBLIC_KEY) + _der_oid(curve_oid))
    return _der_tlv(0x30, algorithm + _der_bit_string(point_bytes))


def build_rsa_spki_der(*, modulus: int, public_exponent: int) -> bytes:
    algorithm = _der_tlv(0x30, _der_oid(OID_RSA_ENCRYPTION) + _der_null())
    rsa_public_key = _der_tlv(0x30, _der_integer(modulus) + _der_integer(public_exponent))
    return _der_tlv(0x30, algorithm + _der_bit_string(rsa_public_key))


def _fingerprint_hex(der: bytes) -> str:
    return hashlib.sha256(der).hexdigest()


# --- manifest generation (E01-17) ---------------------------------------------------------------


def _positive_vector(vector_id: str, description: str, *, private_scalar_label: str) -> dict[str, Any]:
    scalar = _fixed_scalar(private_scalar_label)
    x, y = p256_public_point(scalar)
    point_bytes = _ec_point_uncompressed(x, y, P256_COORD_BYTES)
    der = build_ec_spki_der(curve_oid=OID_PRIME256V1, point_bytes=point_bytes)
    assert len(der) == 91, "uncompressed P-256 SPKI DER MUST be exactly 91 bytes (SPEC.md #1)"
    return {
        "id": vector_id,
        "description": description,
        "input": {"spkiDerHex": der.hex()},
        "expected": {"fingerprintHex": _fingerprint_hex(der)},
    }


def _compressed_point_vector() -> dict[str, Any]:
    scalar = _fixed_scalar("fixture-1")
    x, y = p256_public_point(scalar)
    point_bytes = _ec_point_compressed(x, y, P256_COORD_BYTES)
    der = build_ec_spki_der(curve_oid=OID_PRIME256V1, point_bytes=point_bytes)
    return {
        "id": "spki-fingerprint-compressed-point",
        "description": (
            "Same P-256 key as spki-fingerprint-p256-fixture-1, encoded as a compressed SEC1 "
            "point (0x02/0x03 prefix, X only) instead of the required uncompressed 0x04 prefix "
            "point; MUST be rejected before any fingerprint compare (SPEC.md #1, Certificate "
            "handling)."
        ),
        "input": {"spkiDerHex": der.hex()},
        "expectedError": "unsupportedPointEncoding",
    }


def _p384_curve_vector() -> dict[str, Any]:
    x = int.from_bytes(hashlib.shake_256(b"tandem-vectors:spki-p384-x").digest(P384_COORD_BYTES), "big")
    y = int.from_bytes(hashlib.shake_256(b"tandem-vectors:spki-p384-y").digest(P384_COORD_BYTES), "big")
    point_bytes = _ec_point_uncompressed(x, y, P384_COORD_BYTES)
    der = build_ec_spki_der(curve_oid=OID_SECP384R1, point_bytes=point_bytes)
    return {
        "id": "spki-fingerprint-p384-curve",
        "description": (
            "An uncompressed EC public key on P-384 (secp384r1) rather than P-256: the "
            "AlgorithmIdentifier names the wrong curve OID, so this MUST be rejected as an "
            "unsupported key type before any fingerprint compare (SPEC.md #1)."
        ),
        "input": {"spkiDerHex": der.hex()},
        "expectedError": "unsupportedKeyType",
    }


def _rsa_2048_vector() -> dict[str, Any]:
    modulus_bytes = bytearray(hashlib.shake_256(b"tandem-vectors:spki-rsa-2048-modulus").digest(256))
    modulus_bytes[0] |= 0x80  # keep the modulus a full 2048 bits (leading bit set)
    modulus_bytes[-1] |= 0x01  # keep it odd, as an RSA modulus (product of two odd primes) is
    modulus = int.from_bytes(bytes(modulus_bytes), "big")
    der = build_rsa_spki_der(modulus=modulus, public_exponent=65537)
    return {
        "id": "spki-fingerprint-rsa-2048",
        "description": (
            "An RSA-2048 SubjectPublicKeyInfo (rsaEncryption OID, 2048-bit modulus, exponent "
            "65537): MUST be rejected as an unsupported key type before any fingerprint compare "
            "(SPEC.md #1). The modulus is deterministic filler shaped like a real 2048-bit RSA "
            "modulus (top bit set, odd); this vector exercises key-type rejection, not RSA "
            "validity, so the modulus need not be a genuine product of two primes."
        ),
        "input": {"spkiDerHex": der.hex()},
        "expectedError": "unsupportedKeyType",
    }


def _truncated_der_vector() -> dict[str, Any]:
    scalar = _fixed_scalar("fixture-1")
    x, y = p256_public_point(scalar)
    point_bytes = _ec_point_uncompressed(x, y, P256_COORD_BYTES)
    der = build_ec_spki_der(curve_oid=OID_PRIME256V1, point_bytes=point_bytes)
    truncated = der[:-1]
    return {
        "id": "spki-fingerprint-truncated-der",
        "description": (
            "The same P-256 SPKI DER as spki-fingerprint-p256-fixture-1 with its final byte cut "
            "off (90 of 91 bytes delivered): MUST be rejected as malformed DER before any "
            "fingerprint compare (SPEC.md #1)."
        ),
        "input": {"spkiDerHex": truncated.hex()},
        "expectedError": "malformedSpki",
    }


def generate_spki_fingerprint_vectors() -> dict[str, Any]:
    positive_vectors = [
        _positive_vector(
            f"spki-fingerprint-p256-fixture-{i}",
            f"SHA-256 fingerprint of a fixed, deterministically-derived P-256 SPKI DER (fixture key {i}).",
            private_scalar_label=f"fixture-{i}",
        )
        for i in range(1, 6)
    ]

    vectors = [
        *positive_vectors,
        _compressed_point_vector(),
        _p384_curve_vector(),
        _rsa_2048_vector(),
        _truncated_der_vector(),
    ]

    return {
        "$schema": "./schema.json",
        "category": "spki-fingerprint",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
