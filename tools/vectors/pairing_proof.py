"""Generator for protocol/vectors/pairing-proof.json (E01-18).

Covers `docs/protocol/SPEC.md` #2 "Proof computation" / "Confirmation code": the length-prefixed,
channel-bound pairing proof

    transcript = ASCII("tandem-pair-v1") || LP(macSpkiDer) || LP(phoneSpkiDer) || LP(cb)
    proof = HMAC-SHA256(secret, transcript)

and the 6-digit confirmation code

    code = (u32be(first 4 bytes of HMAC-SHA256(secret, ASCII("tandem-pair-code-v1") ||
            LP(macSpkiDer) || LP(phoneSpkiDer) || LP(cb)))) mod 1000000

where `LP(x) = u16be(len(x)) || x`, `secret` is the 16-byte pairing secret, and `cb` is the
32-byte channel-binding value (`PairChallenge`). Every `proof`-kind vector models the *verifier*
side of the check (SPEC.md: "the Mac MUST recompute `proof` ... then compare ... in constant
time"): `input.secretHex`/`macSpkiDerHex`/`phoneSpkiDerHex`/`cbHex` are always the values the
verifier itself holds/observed on this session, and `input.proofHex` is the candidate value under
test — equal to a correct recomputation for positive vectors, and deliberately computed some other
way (wrong key, wrong secret, swapped/omitted transcript fields, a stale `cb`) for the
`proofMismatch` negative vectors, or structurally invalid (wrong length proof / non-DER SPKI) for
the `malformedProof` / `malformedSpki` vectors.

Real P-256 SPKI DERs are reused from `spki_fingerprint.py` (E01-17) rather than re-implementing
key derivation here, keyed by distinct fixed labels so this category's fixtures don't collide with
E01-17's own `fixture-1..5` fixtures.
"""

from __future__ import annotations

import hashlib
import hmac
from typing import Any

from spki_fingerprint import (
    OID_PRIME256V1,
    P256_COORD_BYTES,
    _ec_point_uncompressed,
    _fixed_scalar,
    build_ec_spki_der,
    p256_public_point,
)

PROOF_LABEL = b"tandem-pair-v1"
CODE_LABEL = b"tandem-pair-code-v1"


def _lp(x: bytes) -> bytes:
    """LP(x) = u16be(len(x)) || x (SPEC.md #2 Proof computation)."""
    return len(x).to_bytes(2, "big") + x


def _fixed_bytes(label: str, length: int) -> bytes:
    digest = hashlib.sha256(f"tandem-vectors:pairing-proof:{label}".encode("ascii")).digest()
    return digest[:length]


def _secret(label: str) -> bytes:
    return _fixed_bytes(f"secret:{label}", 16)


def _cb(label: str) -> bytes:
    return _fixed_bytes(f"cb:{label}", 32)


def _spki_der(label: str) -> bytes:
    """A real, deterministic 91-byte uncompressed P-256 SPKI DER for `label`, built the same way
    as spki_fingerprint.py's own fixtures but keyed under a distinct label namespace."""
    scalar = _fixed_scalar(f"pairing-{label}")
    x, y = p256_public_point(scalar)
    point_bytes = _ec_point_uncompressed(x, y, P256_COORD_BYTES)
    der = build_ec_spki_der(curve_oid=OID_PRIME256V1, point_bytes=point_bytes)
    assert len(der) == 91, "uncompressed P-256 SPKI DER MUST be exactly 91 bytes (SPEC.md #1)"
    return der


def _raw_point(label: str) -> bytes:
    """The 65-byte raw SEC1 uncompressed point (0x04 || X || Y) for the same key as
    `_spki_der(label)`, without the SubjectPublicKeyInfo DER envelope -- used to build the
    malformedSpki vector (a 91-byte SPKI DER is required, SPEC.md #2)."""
    scalar = _fixed_scalar(f"pairing-{label}")
    x, y = p256_public_point(scalar)
    return _ec_point_uncompressed(x, y, P256_COORD_BYTES)


def _proof_transcript(mac_spki_der: bytes, phone_spki_der: bytes, cb: bytes) -> bytes:
    return PROOF_LABEL + _lp(mac_spki_der) + _lp(phone_spki_der) + _lp(cb)


def _proof(secret: bytes, mac_spki_der: bytes, phone_spki_der: bytes, cb: bytes) -> bytes:
    return hmac.new(secret, _proof_transcript(mac_spki_der, phone_spki_der, cb), hashlib.sha256).digest()


def _code_transcript(mac_spki_der: bytes, phone_spki_der: bytes, cb: bytes) -> bytes:
    return CODE_LABEL + _lp(mac_spki_der) + _lp(phone_spki_der) + _lp(cb)


def _code(secret: bytes, mac_spki_der: bytes, phone_spki_der: bytes, cb: bytes) -> str:
    digest = hmac.new(secret, _code_transcript(mac_spki_der, phone_spki_der, cb), hashlib.sha256).digest()
    value = int.from_bytes(digest[:4], "big") % 1_000_000
    return f"{value:06d}"


def _proof_vector(
    vector_id: str,
    description: str,
    *,
    secret: bytes,
    mac_spki_der: bytes,
    phone_spki_der: bytes,
    cb: bytes,
    proof: bytes,
    expected_error: str | None = None,
) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "id": vector_id,
        "description": description,
        "input": {
            "kind": "proof",
            "secretHex": secret.hex(),
            "macSpkiDerHex": mac_spki_der.hex(),
            "phoneSpkiDerHex": phone_spki_der.hex(),
            "cbHex": cb.hex(),
            "proofHex": proof.hex(),
        },
    }
    if expected_error is None:
        entry["expected"] = {"valid": True}
    else:
        entry["expectedError"] = expected_error
        entry["closeCode"] = "PAIRING_FAILED"
        entry["localReason"] = "MALFORMED" if expected_error in ("malformedProof", "malformedSpki") else "BAD_PROOF"
    return entry


def _code_vector(
    vector_id: str,
    description: str,
    *,
    secret: bytes,
    mac_spki_der: bytes,
    phone_spki_der: bytes,
    cb: bytes,
) -> dict[str, Any]:
    return {
        "id": vector_id,
        "description": description,
        "input": {
            "kind": "code",
            "secretHex": secret.hex(),
            "macSpkiDerHex": mac_spki_der.hex(),
            "phoneSpkiDerHex": phone_spki_der.hex(),
            "cbHex": cb.hex(),
        },
        "expected": {"code": _code(secret, mac_spki_der, phone_spki_der, cb)},
    }


def _generate_proof_vectors() -> list[dict[str, Any]]:
    vectors: list[dict[str, Any]] = []

    positive_fixtures = ["a", "b", "c", "d", "e"]
    for suffix in positive_fixtures:
        secret = _secret(f"secret-{suffix}")
        mac_der = _spki_der(f"mac-{suffix}")
        phone_der = _spki_der(f"phone-{suffix}")
        cb = _cb(f"cb-{suffix}")
        proof = _proof(secret, mac_der, phone_der, cb)
        vectors.append(
            _proof_vector(
                f"pairing-proof-correct-{suffix}",
                f"HMAC-SHA256 pairing proof over the correctly length-prefixed transcript, "
                f"fixture combo {suffix} (SPEC.md #2 Proof computation).",
                secret=secret,
                mac_spki_der=mac_der,
                phone_spki_der=phone_der,
                cb=cb,
                proof=proof,
            )
        )

    # Baseline "a" values, reused below as the verifier's own (correct) session state; each
    # negative vector supplies a `proofHex` computed some other way than the correct transcript.
    secret_a = _secret("secret-a")
    mac_a = _spki_der("mac-a")
    phone_a = _spki_der("phone-a")
    cb_a = _cb("cb-a")

    phone_wrong = _spki_der("phone-wrong")
    vectors.append(
        _proof_vector(
            "pairing-proof-wrong-phone-key",
            "proof computed by the attacker with a different phoneSpkiDer than the one actually "
            "observed on this session's TLS handshake; the verifier recomputes with its own "
            "observed phoneSpkiDer and MUST reject (SPEC.md #2, for use by mitm-lab E15-09).",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_a,
            proof=_proof(secret_a, mac_a, phone_wrong, cb_a),
            expected_error="proofMismatch",
        )
    )

    secret_wrong = _secret("secret-wrong")
    vectors.append(
        _proof_vector(
            "pairing-proof-wrong-secret",
            "proof computed with a different 16-byte pairing secret than the one from the QR "
            "`s` field; the verifier recomputes with the correct secret and MUST reject.",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_a,
            proof=_proof(secret_wrong, mac_a, phone_a, cb_a),
            expected_error="proofMismatch",
        )
    )

    swapped_transcript = PROOF_LABEL + _lp(phone_a) + _lp(mac_a) + _lp(cb_a)
    vectors.append(
        _proof_vector(
            "pairing-proof-swapped-spki-order",
            "proof computed with macSpkiDer and phoneSpkiDer swapped in the transcript "
            "(LP(phoneSpkiDer) || LP(macSpkiDer) instead of the required order); MUST reject.",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_a,
            proof=hmac.new(secret_a, swapped_transcript, hashlib.sha256).digest(),
            expected_error="proofMismatch",
        )
    )

    no_label_transcript = _lp(mac_a) + _lp(phone_a) + _lp(cb_a)
    vectors.append(
        _proof_vector(
            "pairing-proof-missing-label",
            "proof computed over the transcript with the ASCII(\"tandem-pair-v1\") label "
            "omitted entirely; MUST reject.",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_a,
            proof=hmac.new(secret_a, no_label_transcript, hashlib.sha256).digest(),
            expected_error="proofMismatch",
        )
    )

    raw_concat_transcript = PROOF_LABEL + mac_a + phone_a + cb_a
    vectors.append(
        _proof_vector(
            "pairing-proof-raw-concatenation-no-length-prefix",
            "proof computed by raw-concatenating macSpkiDer/phoneSpkiDer/cb with no 2-byte "
            "length prefixes at all, instead of the required LP(x) = u16be(len(x)) || x "
            "encoding; MUST reject.",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_a,
            proof=hmac.new(secret_a, raw_concat_transcript, hashlib.sha256).digest(),
            expected_error="proofMismatch",
        )
    )

    cb_other = _cb("cb-other-session")
    vectors.append(
        _proof_vector(
            "pairing-proof-different-channel-binding",
            "proof valid for a different session's `cb` (same secret and keys), replayed against "
            "this session whose actual `cb` differs -- a cross-session replay; the verifier "
            "recomputes with its own session's `cb` and MUST reject (SPEC.md #1 Channel binding, "
            "#2 Proof computation).",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_a,
            proof=_proof(secret_a, mac_a, phone_a, cb_other),
            expected_error="proofMismatch",
        )
    )

    phone_raw_point = _raw_point("phone-a")
    vectors.append(
        _proof_vector(
            "pairing-proof-raw-point-instead-of-spki-der",
            "phoneSpkiDer replaced by the 65-byte raw SEC1 uncompressed point (0x04 || X || Y) "
            "for the same key, instead of the required 91-byte SubjectPublicKeyInfo DER; MUST be "
            "rejected as malformed before any HMAC compare runs (SPEC.md #2).",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_raw_point,
            cb=cb_a,
            proof=_proof(secret_a, mac_a, phone_a, cb_a),
            expected_error="malformedSpki",
        )
    )

    full_proof_a = _proof(secret_a, mac_a, phone_a, cb_a)
    vectors.append(
        _proof_vector(
            "pairing-proof-31-byte-proof",
            "an otherwise-correct 32-byte HMAC-SHA256 proof with its last byte cut off (31 of 32 "
            "bytes delivered); MUST be rejected as malformed before any HMAC compare runs.",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_a,
            proof=full_proof_a[:-1],
            expected_error="malformedProof",
        )
    )

    return vectors


def _generate_code_vectors() -> list[dict[str, Any]]:
    secret_a = _secret("secret-a")
    mac_a = _spki_der("mac-a")
    phone_a = _spki_der("phone-a")
    cb_a = _cb("cb-a")

    vectors = [
        _code_vector(
            "pairing-code-fixture-a",
            "6-digit confirmation code for fixture combo a (SPEC.md #2 Confirmation code).",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_a,
        )
    ]

    # Deterministic search (fixed order, first match) for a secret whose resulting code is below
    # 100000, i.e. rendered with at least one leading zero when zero-padded to 6 digits.
    leading_zero_secret: bytes | None = None
    leading_zero_code: str | None = None
    for i in range(1, 10_000):
        candidate_secret = _secret(f"secret-leading-zero-{i}")
        candidate_code = _code(candidate_secret, mac_a, phone_a, cb_a)
        if candidate_code.startswith("0"):
            leading_zero_secret = candidate_secret
            leading_zero_code = candidate_code
            break
    assert leading_zero_secret is not None and leading_zero_code is not None, (
        "no leading-zero confirmation code found in the deterministic search space"
    )
    vectors.append(
        _code_vector(
            "pairing-code-leading-zero",
            f"confirmation code {leading_zero_code!r} has a leading zero and MUST still be "
            "rendered as exactly 6 digits (SPEC.md #2, e.g. `007042`).",
            secret=leading_zero_secret,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_a,
        )
    )

    cb_diff = _cb("cb-diff-code")
    vectors.append(
        _code_vector(
            "pairing-code-different-channel-binding",
            "same secret and keys as pairing-code-fixture-a but a different `cb`: the resulting "
            "code MUST differ from pairing-code-fixture-a's.",
            secret=secret_a,
            mac_spki_der=mac_a,
            phone_spki_der=phone_a,
            cb=cb_diff,
        )
    )

    mac_relay = _spki_der("mac-relay-forwarded-challenge")
    vectors.append(
        _code_vector(
            "pairing-code-forwarded-challenge-relay",
            "the forwarded-challenge evil-QR/relay case (`docs/planning/decisions.md` D-71): "
            "identical `secret` and `cb` to pairing-code-fixture-a, but a different macSpkiDer "
            "(the attacker's own key on this side of the relay). The resulting code MUST still "
            "differ from pairing-code-fixture-a's, proving detection rests on the SPKI pair, not "
            "on `cb` (SPEC.md #2 Confirmation code).",
            secret=secret_a,
            mac_spki_der=mac_relay,
            phone_spki_der=phone_a,
            cb=cb_a,
        )
    )

    return vectors


def generate_pairing_proof_vectors() -> dict[str, Any]:
    vectors = [*_generate_proof_vectors(), *_generate_code_vectors()]

    return {
        "$schema": "./schema.json",
        "category": "pairing-proof",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
