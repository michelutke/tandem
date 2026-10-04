"""Generator for protocol/vectors/rotation-encoding.json (E70-01).

Covers `docs/protocol/SPEC.md` #key-rotation: the message types of `rotation.proto`

    RotationChallenge { challenge (bytes, 1) }
    KeyRotation { new_spki_der (bytes, 1), sig_old_key (bytes, 2), sig_new_key (bytes, 3) }
    RotationAck {}
    RotationReject { reason (RotationRejectReason enum, 1) }

and the KeyRotation signature check. Both signatures are ECDSA P-256 / SHA-256 (ASN.1 DER) over

    transcript = ASCII("tandem-rotate-v1") || LP(oldSpkiDer) || LP(newSpkiDer) || LP(cb)

with `LP(x) = u16be(len(x)) || x` and `cb` the verifier's own `RotationChallenge` for the session.

`input.kind` selects the vector type. `rotationChallenge`/`rotationAck`/`rotationReject` carry
`input.messageHex`. A `keyRotation` entry models the *verifier* side: `input.oldSpkiDerHex` (the key
authenticated on the session) and `input.cbHex` (the verifier's challenge) are what the verifier
itself holds, `input.messageHex` is the received serialized KeyRotation. Positive entries expect
`{"valid": true}`; negative entries carry `expectedError: "invalidSignature"` (receiver replies
RotationReject INVALID_SIGNATURE, no close). Before verifying, `newSpkiDer` must be exactly the 91-byte
uncompressed P-256 SPKI (SPEC #key-rotation step 5); anything else is `invalidSignature`.

Signatures are made with RFC 6979 deterministic ECDSA (HMAC-SHA256) so regeneration is byte-stable.
"""

from __future__ import annotations

import hashlib
import hmac
from typing import Any

from spki_fingerprint import (
    OID_PRIME256V1,
    OID_SECP384R1,
    P384_COORD_BYTES,
    P256_COORD_BYTES,
    P256_GX,
    P256_GY,
    P256_N,
    _der_integer,
    _der_tlv,
    _ec_point_compressed,
    _ec_point_uncompressed,
    _fixed_scalar,
    _inverse_mod,
    _scalar_mult,
    build_ec_spki_der,
    p256_public_point,
)

ROTATE_LABEL = b"tandem-rotate-v1"
CHALLENGE_LENGTH = 32

REJECT_REASONS = {
    "INVALID_SIGNATURE": 1,
    "UNAUTHENTICATED_SESSION": 2,
    "NOT_PRIMARY_PIN": 3,
    "DUPLICATE_KEY": 4,
    "ROTATION_UNAVAILABLE": 5,
}


def _varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def _field_bytes(field_number: int, value: bytes) -> bytes:
    if not value:
        return b""
    return _varint((field_number << 3) | 2) + _varint(len(value)) + value


def _field_varint(field_number: int, value: int) -> bytes:
    if not value:
        return b""
    return _varint(field_number << 3) + _varint(value)


def _lp(x: bytes) -> bytes:
    return len(x).to_bytes(2, "big") + x


def _scalar(label: str) -> int:
    return _fixed_scalar(f"rotation-{label}")


def _spki_der(label: str) -> bytes:
    x, y = p256_public_point(_scalar(label))
    der = build_ec_spki_der(
        curve_oid=OID_PRIME256V1,
        point_bytes=_ec_point_uncompressed(x, y, P256_COORD_BYTES),
    )
    assert len(der) == 91
    return der


def _challenge(label: str) -> bytes:
    return hashlib.sha256(f"tandem-vectors:rotation:cb:{label}".encode("ascii")).digest()


def _transcript(old_spki_der: bytes, new_spki_der: bytes, cb: bytes) -> bytes:
    return ROTATE_LABEL + _lp(old_spki_der) + _lp(new_spki_der) + _lp(cb)


def _rfc6979_k(private_scalar: int, digest: bytes) -> int:
    x = private_scalar.to_bytes(32, "big")
    h1 = (int.from_bytes(digest, "big") % P256_N).to_bytes(32, "big")
    v = b"\x01" * 32
    k = b"\x00" * 32
    k = hmac.new(k, v + b"\x00" + x + h1, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    k = hmac.new(k, v + b"\x01" + x + h1, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    while True:
        v = hmac.new(k, v, hashlib.sha256).digest()
        candidate = int.from_bytes(v, "big")
        if 1 <= candidate < P256_N:
            return candidate
        k = hmac.new(k, v + b"\x00", hashlib.sha256).digest()
        v = hmac.new(k, v, hashlib.sha256).digest()


def _sign(private_scalar: int, message: bytes) -> bytes:
    """ECDSA P-256 / SHA-256, deterministic (RFC 6979), ASN.1 DER SEQUENCE { r, s }."""
    digest = hashlib.sha256(message).digest()
    z = int.from_bytes(digest, "big")
    k = _rfc6979_k(private_scalar, digest)
    r = _scalar_mult(k, (P256_GX, P256_GY))[0] % P256_N
    s = (_inverse_mod(k, P256_N) * (z + r * private_scalar)) % P256_N
    assert r and s
    return _der_tlv(0x30, _der_integer(r) + _der_integer(s))


def encode_key_rotation(*, new_spki_der: bytes, sig_old_key: bytes, sig_new_key: bytes) -> bytes:
    return _field_bytes(1, new_spki_der) + _field_bytes(2, sig_old_key) + _field_bytes(3, sig_new_key)


def _rotation(old: str, new: str, cb: bytes, *, sign_old_with: str | None = None, sign_new_with: str | None = None) -> bytes:
    old_der, new_der = _spki_der(old), _spki_der(new)
    transcript = _transcript(old_der, new_der, cb)
    return encode_key_rotation(
        new_spki_der=new_der,
        sig_old_key=_sign(_scalar(sign_old_with or old), transcript),
        sig_new_key=_sign(_scalar(sign_new_with or new), transcript),
    )


def _p384_spki_der() -> bytes:
    x = int.from_bytes(hashlib.shake_256(b"tandem-vectors:rotation-p384-x").digest(P384_COORD_BYTES), "big")
    y = int.from_bytes(hashlib.shake_256(b"tandem-vectors:rotation-p384-y").digest(P384_COORD_BYTES), "big")
    return build_ec_spki_der(
        curve_oid=OID_SECP384R1, point_bytes=_ec_point_uncompressed(x, y, P384_COORD_BYTES)
    )


def _compressed_spki_der(label: str) -> bytes:
    x, y = p256_public_point(_scalar(label))
    return build_ec_spki_der(
        curve_oid=OID_PRIME256V1, point_bytes=_ec_point_compressed(x, y, P256_COORD_BYTES)
    )


def _rotation_with_new_der(old: str, new_der: bytes, cb: bytes) -> bytes:
    transcript = _transcript(_spki_der(old), new_der, cb)
    return encode_key_rotation(
        new_spki_der=new_der,
        sig_old_key=_sign(_scalar(old), transcript),
        sig_new_key=_sign(_scalar("new"), transcript),
    )


def _key_rotation_vector(
    slug: str, description: str, message: bytes, *, verifier_old: str, verifier_cb: bytes, valid: bool
) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "id": f"key-rotation-{slug}",
        "description": description,
        "input": {
            "kind": "keyRotation",
            "oldSpkiDerHex": _spki_der(verifier_old).hex(),
            "cbHex": verifier_cb.hex(),
            "messageHex": message.hex(),
        },
    }
    if valid:
        entry["expected"] = {"valid": True, "messageSha256": hashlib.sha256(message).hexdigest()}
    else:
        entry["expectedError"] = "invalidSignature"
    return entry


def generate_rotation_encoding_vectors() -> dict[str, Any]:
    """Generates rotation message and KeyRotation signature vectors."""

    cb = _challenge("session-a")
    other_cb = _challenge("session-b")
    good = _rotation("old", "new", cb)
    other_new_der = _spki_der("other-new")
    good_new_der = _spki_der("new")
    tampered_msg = good.replace(good_new_der, other_new_der)
    assert tampered_msg != good
    truncated = encode_key_rotation(
        new_spki_der=good_new_der,
        sig_old_key=_sign(_scalar("old"), _transcript(_spki_der("old"), good_new_der, cb))[:-8],
        sig_new_key=_sign(_scalar("new"), _transcript(_spki_der("old"), good_new_der, cb)),
    )

    challenge_msg = _field_bytes(1, cb)
    ack_msg = b""
    reject_msgs = {name: _field_varint(1, value) for name, value in REJECT_REASONS.items()}

    p384_der = _p384_spki_der()
    compressed_der = _compressed_spki_der("new")

    vectors: list[dict[str, Any]] = [
        {
            "id": "rotation-challenge-round-trip",
            "description": "RotationChallenge with a 32-byte challenge round-tripping to golden bytes.",
            "input": {"kind": "rotationChallenge", "messageHex": challenge_msg.hex()},
            "expected": {
                "challengeHex": cb.hex(),
                "messageSha256": hashlib.sha256(challenge_msg).hexdigest(),
            },
        },
        {
            "id": "rotation-ack-round-trip",
            "description": "RotationAck, an empty message, round-tripping to golden zero-length bytes.",
            "input": {"kind": "rotationAck", "messageHex": ack_msg.hex()},
            "expected": {"messageSha256": hashlib.sha256(ack_msg).hexdigest()},
        },
    ]
    for name, msg in reject_msgs.items():
        vectors.append(
            {
                "id": f"rotation-reject-{name.lower().replace('_', '-')}-round-trip",
                "description": f"RotationReject reason {name} round-tripping to golden bytes.",
                "input": {"kind": "rotationReject", "messageHex": msg.hex()},
                "expected": {"reason": name, "messageSha256": hashlib.sha256(msg).hexdigest()},
            }
        )
    vectors += [
        _key_rotation_vector(
            "old-key-signature-over-new-spki",
            "KeyRotation signed by the old key and by the new key over the cycle-4 transcript verifies; "
            "re-encodes to the same golden bytes.",
            good, verifier_old="old", verifier_cb=cb, valid=True,
        ),
        _key_rotation_vector(
            "tampered-new-spki",
            "newSpkiDer replaced by another valid key after signing: both signatures fail.",
            tampered_msg, verifier_old="old", verifier_cb=cb, valid=False,
        ),
        _key_rotation_vector(
            "signed-by-new-key-instead-of-old",
            "sigOldKey made by the new key instead of the old key: fails.",
            _rotation("old", "new", cb, sign_old_with="new"), verifier_old="old", verifier_cb=cb, valid=False,
        ),
        _key_rotation_vector(
            "wrong-old-key",
            "sigOldKey made by an unrelated key, not the key authenticated on the session: fails.",
            _rotation("old", "new", cb, sign_old_with="stranger"), verifier_old="old", verifier_cb=cb, valid=False,
        ),
        _key_rotation_vector(
            "truncated-der-signature",
            "sigOldKey truncated by 8 bytes (invalid DER): verification fails.",
            truncated, verifier_old="old", verifier_cb=cb, valid=False,
        ),
        _key_rotation_vector(
            "other-rotation-challenge-value",
            "Signatures made over another session's RotationChallenge (replay onto this session): fails.",
            _rotation("old", "new", other_cb), verifier_old="old", verifier_cb=cb, valid=False,
        ),
        _key_rotation_vector(
            "invalid-new-key-proof-of-possession",
            "sigNewKey made by a key other than newSpkiDer (claiming someone else's public key): fails.",
            _rotation("old", "new", cb, sign_new_with="stranger"), verifier_old="old", verifier_cb=cb, valid=False,
        ),
        _key_rotation_vector(
            "p384-new-spki",
            "newSpkiDer is a P-384 SPKI (120 bytes) instead of the required 91-byte P-256 SPKI: rejected "
            "before signature verification.",
            _rotation_with_new_der("old", p384_der, cb), verifier_old="old", verifier_cb=cb, valid=False,
        ),
        _key_rotation_vector(
            "compressed-point-new-spki",
            "newSpkiDer is a P-256 SPKI with a compressed point (59 bytes) instead of the uncompressed "
            "0x04 point: rejected before signature verification.",
            _rotation_with_new_der("old", compressed_der, cb), verifier_old="old", verifier_cb=cb, valid=False,
        ),
    ]

    return {
        "$schema": "./schema.json",
        "category": "rotation-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
