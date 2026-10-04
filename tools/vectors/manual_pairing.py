"""Generator for protocol/vectors/manual-pairing.json (E73-02).

Covers `docs/protocol/SPEC.md` #manual-pairing (ADR-008): the messages of `manual_pairing.proto`

    Commitment { hash (bytes, 1) }  Reveal { nonce (bytes, 1) }  ManualPairResult { accepted (bool, 1) }

and the commit-then-reveal SAS derived from them:

    ctx = ASCII("tandem-manual-pair-v1") || LP(macSpkiDer) || LP(phoneSpkiDer) || LP(cb)
    commitX = SHA-256(ASCII("tandem-manual-commit-v1") || roleByte || nonceX || ctx)   (phone 0x01, Mac 0x02)
    h = HMAC-SHA256(key = nonceP || nonceM, msg = ASCII("tandem-manual-pair-v1") || ctx)
    sas = u64be(h[0:8]) mod 1000000, zero-padded to 6 digits

with `LP(x) = u16be(len(x)) || x`. `input.kind` selects the vector type:

- `message`: `input.messageType` (`commitment`|`reveal`|`manualPairResult`) and `input.messageHex`, a
  serialized message. Positive entries carry `expected.summary` and `expected.messageSha256` and
  re-encode to the same bytes; negative entries carry `expectedError` (`malformedCommitment`,
  `malformedReveal`, `resultNotAccepted`).
- `sas`: both nonces, both SPKIs and `cb`; `expected` has both commitments, the HMAC and the 6-digit `sas`.
- `commitment`: the *verifier* side of step 4. `input.committerRole` is the role the commitment is
  attributed to, `input.commitmentHex` the received Commitment, `input.revealNonceHex` the received
  Reveal and the SPKIs/`cb` are what the verifier itself observed. Negative entries carry
  `expectedError: "commitmentMismatch"` (`closeCode` PAIRING_FAILED, one attempt burned).
- `sasCompare`: `input.phoneView` and `input.macView` each hold the values one side used; the owner
  compares the codes. Positive entries expect `{"match": true, "sas": ...}`, negative entries
  `expectedError: "sasMismatch"` (terminal for the window).
- `sequence`: `input.messages` is the ordered list of `{from, type}` seen on a manual window; a
  complete valid exchange expects `{"complete": true}`, any deviation `expectedError: "outOfOrder"`
  (`closeCode` PAIRING_FAILED, one attempt burned).
"""

from __future__ import annotations

import hashlib
import hmac
from typing import Any

from media_encoding import _field_bytes, _field_varint
from pairing_proof import _lp, _spki_der

PAIR_LABEL = b"tandem-manual-pair-v1"
COMMIT_LABEL = b"tandem-manual-commit-v1"
ROLE_BYTE = {"phone": 0x01, "mac": 0x02}
NONCE_LENGTH = 16
HASH_LENGTH = 32
SAS_MODULUS = 1_000_000

VALID_SEQUENCE = [
    ("phone", "commitment"),
    ("mac", "commitment"),
    ("phone", "reveal"),
    ("mac", "reveal"),
    ("mac", "manualPairResult"),
]


def _fixed_bytes(label: str, length: int) -> bytes:
    return hashlib.sha256(f"tandem-vectors:manual-pairing:{label}".encode("ascii")).digest()[:length]


def _nonce(label: str) -> bytes:
    return _fixed_bytes(f"nonce:{label}", NONCE_LENGTH)


def _cb(label: str) -> bytes:
    return _fixed_bytes(f"cb:{label}", 32)


def _ctx(mac_spki: bytes, phone_spki: bytes, cb: bytes) -> bytes:
    return PAIR_LABEL + _lp(mac_spki) + _lp(phone_spki) + _lp(cb)


def _commit(role: str, nonce: bytes, mac_spki: bytes, phone_spki: bytes, cb: bytes) -> bytes:
    return hashlib.sha256(COMMIT_LABEL + bytes([ROLE_BYTE[role]]) + nonce + _ctx(mac_spki, phone_spki, cb)).digest()


def _hmac(nonce_p: bytes, nonce_m: bytes, mac_spki: bytes, phone_spki: bytes, cb: bytes) -> bytes:
    message = PAIR_LABEL + _ctx(mac_spki, phone_spki, cb)
    return hmac.new(nonce_p + nonce_m, message, hashlib.sha256).digest()


def _sas(nonce_p: bytes, nonce_m: bytes, mac_spki: bytes, phone_spki: bytes, cb: bytes) -> str:
    digest = _hmac(nonce_p, nonce_m, mac_spki, phone_spki, cb)
    return f"{int.from_bytes(digest[:8], 'big') % SAS_MODULUS:06d}"


def encode_commitment(hash_bytes: bytes) -> bytes:
    return _field_bytes(1, hash_bytes)


def encode_reveal(nonce: bytes) -> bytes:
    return _field_bytes(1, nonce)


def encode_manual_pair_result(*, accepted: bool) -> bytes:
    return _field_varint(1, 1) if accepted else b""


def _view(nonce_p: bytes, nonce_m: bytes, mac_spki: bytes, phone_spki: bytes, cb: bytes) -> dict[str, str]:
    return {
        "noncePhoneHex": nonce_p.hex(),
        "nonceMacHex": nonce_m.hex(),
        "macSpkiDerHex": mac_spki.hex(),
        "phoneSpkiDerHex": phone_spki.hex(),
        "cbHex": cb.hex(),
    }


def _message_positive(vector_id: str, description: str, message_type: str, body: bytes, summary: str) -> dict[str, Any]:
    return {
        "id": vector_id,
        "description": description,
        "input": {"kind": "message", "messageType": message_type, "messageHex": body.hex()},
        "expected": {"summary": summary, "messageSha256": hashlib.sha256(body).hexdigest()},
    }


def _message_negative(vector_id: str, description: str, message_type: str, body: bytes, error: str) -> dict[str, Any]:
    return {
        "id": vector_id,
        "description": description,
        "input": {"kind": "message", "messageType": message_type, "messageHex": body.hex()},
        "expectedError": error,
    }


def _message_vectors() -> list[dict[str, Any]]:
    commit_hash = _fixed_bytes("commitment-hash", HASH_LENGTH)
    nonce = _nonce("reveal-golden")
    return [
        _message_positive(
            "manual-pairing-commitment-round-trip",
            "Commitment with a 32-byte hash round-tripping to golden bytes.",
            "commitment",
            encode_commitment(commit_hash),
            f"type=commitment|hash={commit_hash.hex()}",
        ),
        _message_positive(
            "manual-pairing-reveal-round-trip",
            "Reveal with a 16-byte nonce round-tripping to golden bytes.",
            "reveal",
            encode_reveal(nonce),
            f"type=reveal|nonce={nonce.hex()}",
        ),
        _message_positive(
            "manual-pairing-result-accepted-round-trip",
            "ManualPairResult accepted=true round-tripping to golden bytes.",
            "manualPairResult",
            encode_manual_pair_result(accepted=True),
            "type=manualPairResult|accepted=true",
        ),
        _message_negative(
            "manual-pairing-commitment-short-hash",
            "Commitment whose hash is 31 bytes is rejected PAIRING_FAILED.",
            "commitment",
            encode_commitment(commit_hash[:-1]),
            "malformedCommitment",
        ),
        _message_negative(
            "manual-pairing-commitment-empty",
            "Commitment without a hash is rejected.",
            "commitment",
            b"",
            "malformedCommitment",
        ),
        _message_negative(
            "manual-pairing-reveal-short-nonce",
            "Reveal whose nonce is 15 bytes is rejected.",
            "reveal",
            encode_reveal(nonce[:-1]),
            "malformedReveal",
        ),
        _message_negative(
            "manual-pairing-reveal-long-nonce",
            "Reveal whose nonce is 17 bytes is rejected.",
            "reveal",
            encode_reveal(nonce + b"\x00"),
            "malformedReveal",
        ),
        _message_negative(
            "manual-pairing-result-not-accepted",
            "ManualPairResult with accepted=false (an empty message) is rejected; a decline is PairRejected.",
            "manualPairResult",
            encode_manual_pair_result(accepted=False),
            "resultNotAccepted",
        ),
    ]


def _sas_vector(vector_id: str, description: str, label: str, *, spki_label: str | None = None) -> dict[str, Any]:
    nonce_p, nonce_m = _nonce(f"{label}-phone"), _nonce(f"{label}-mac")
    mac_spki, phone_spki = _spki_der(f"manual-mac-{spki_label or label}"), _spki_der(f"manual-phone-{spki_label or label}")
    cb = _cb(label)
    return {
        "id": vector_id,
        "description": description,
        "input": {"kind": "sas", **_view(nonce_p, nonce_m, mac_spki, phone_spki, cb)},
        "expected": {
            "commitPhoneHex": _commit("phone", nonce_p, mac_spki, phone_spki, cb).hex(),
            "commitMacHex": _commit("mac", nonce_m, mac_spki, phone_spki, cb).hex(),
            "hmacHex": _hmac(nonce_p, nonce_m, mac_spki, phone_spki, cb).hex(),
            "sas": _sas(nonce_p, nonce_m, mac_spki, phone_spki, cb),
        },
    }


def _leading_zero_label() -> str:
    for index in range(10_000):
        label = f"zero-{index}"
        vector = _sas_vector("probe", "probe", label)
        if vector["expected"]["sas"].startswith("0"):
            return label
    raise AssertionError("no leading-zero SAS fixture found")


def _sas_vectors() -> list[dict[str, Any]]:
    return [
        _sas_vector("manual-pairing-sas-a", "Known nonce pair, SPKIs and cb derive a fixed 6-digit SAS (fixture a).", "a"),
        _sas_vector("manual-pairing-sas-b", "Known nonce pair, SPKIs and cb derive a fixed 6-digit SAS (fixture b).", "b"),
        _sas_vector(
            "manual-pairing-sas-leading-zero",
            "A SAS below 100000 is zero-padded to exactly 6 digits.",
            _leading_zero_label(),
        ),
    ]


def _commitment_vector(
    vector_id: str,
    description: str,
    *,
    role: str,
    commitment: bytes,
    reveal_nonce: bytes,
    mac_spki: bytes,
    phone_spki: bytes,
    cb: bytes,
    error: str | None = None,
) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "id": vector_id,
        "description": description,
        "input": {
            "kind": "commitment",
            "committerRole": role,
            "commitmentHex": commitment.hex(),
            "revealNonceHex": reveal_nonce.hex(),
            "macSpkiDerHex": mac_spki.hex(),
            "phoneSpkiDerHex": phone_spki.hex(),
            "cbHex": cb.hex(),
        },
    }
    if error is None:
        entry["expected"] = {"valid": True}
    else:
        entry["expectedError"] = error
        entry["closeCode"] = "PAIRING_FAILED"
    return entry


def _commitment_vectors() -> list[dict[str, Any]]:
    nonce_p, nonce_m = _nonce("commit-phone"), _nonce("commit-mac")
    mac, phone = _spki_der("manual-mac-commit"), _spki_der("manual-phone-commit")
    cb = _cb("commit")
    other_cb = _cb("commit-other-session")
    other_mac = _spki_der("manual-mac-relay")
    commit_p = _commit("phone", nonce_p, mac, phone, cb)
    commit_m = _commit("mac", nonce_m, mac, phone, cb)
    base = {"mac_spki": mac, "phone_spki": phone, "cb": cb}
    return [
        _commitment_vector(
            "manual-pairing-commitment-phone-valid",
            "The phone's Reveal matches its Commitment as the Mac recomputes it.",
            role="phone", commitment=commit_p, reveal_nonce=nonce_p, **base,
        ),
        _commitment_vector(
            "manual-pairing-commitment-mac-valid",
            "The Mac's Reveal matches its Commitment as the phone recomputes it.",
            role="mac", commitment=commit_m, reveal_nonce=nonce_m, **base,
        ),
        _commitment_vector(
            "manual-pairing-commitment-reveal-not-matching",
            "A Reveal whose nonce differs from the committed one fails verification.",
            role="phone", commitment=commit_p, reveal_nonce=_nonce("commit-phone-other"), error="commitmentMismatch", **base,
        ),
        _commitment_vector(
            "manual-pairing-commitment-peer-nonce-as-reveal",
            "The Mac's nonce presented as the phone's Reveal fails verification.",
            role="phone", commitment=commit_p, reveal_nonce=nonce_m, error="commitmentMismatch", **base,
        ),
        _commitment_vector(
            "manual-pairing-commitment-replay-other-cb",
            "A Commitment/Reveal pair recorded under another session's cb fails here.",
            role="phone",
            commitment=_commit("phone", nonce_p, mac, phone, other_cb),
            reveal_nonce=nonce_p,
            error="commitmentMismatch",
            **base,
        ),
        _commitment_vector(
            "manual-pairing-commitment-replay-other-spki",
            "A Commitment made against a different Mac SPKI (a relay leg) fails here.",
            role="phone",
            commitment=_commit("phone", nonce_p, other_mac, phone, cb),
            reveal_nonce=nonce_p,
            error="commitmentMismatch",
            **base,
        ),
        _commitment_vector(
            "manual-pairing-commitment-reflected-role",
            "The phone's Commitment reflected back and attributed to the Mac fails (role byte).",
            role="mac", commitment=commit_p, reveal_nonce=nonce_p, error="commitmentMismatch", **base,
        ),
    ]


def _compare_vector(
    vector_id: str, description: str, phone_view: dict[str, str], mac_view: dict[str, str], sas_phone: str, sas_mac: str
) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "id": vector_id,
        "description": description,
        "input": {"kind": "sasCompare", "phoneView": phone_view, "macView": mac_view},
    }
    if sas_phone == sas_mac:
        entry["expected"] = {"match": True, "sas": sas_phone}
    else:
        entry["expectedError"] = "sasMismatch"
    return entry


def _sas_of(view: dict[str, str]) -> str:
    return _sas(
        bytes.fromhex(view["noncePhoneHex"]),
        bytes.fromhex(view["nonceMacHex"]),
        bytes.fromhex(view["macSpkiDerHex"]),
        bytes.fromhex(view["phoneSpkiDerHex"]),
        bytes.fromhex(view["cbHex"]),
    )


def _compare_vectors() -> list[dict[str, Any]]:
    nonce_p, nonce_m = _nonce("compare-phone"), _nonce("compare-mac")
    mac, phone, cb = _spki_der("manual-mac-compare"), _spki_der("manual-phone-compare"), _cb("compare")
    honest = _view(nonce_p, nonce_m, mac, phone, cb)
    cases = [
        ("manual-pairing-sas-compare-honest", "Both sides derive the same SAS.", honest, honest),
        (
            "manual-pairing-sas-compare-relay-spki",
            "A relay's own Mac key on the phone leg changes ctx; the codes differ.",
            _view(nonce_p, nonce_m, _spki_der("manual-mac-relay"), phone, cb),
            honest,
        ),
        (
            "manual-pairing-sas-compare-other-cb",
            "A different channel binding on one leg changes ctx; the codes differ.",
            honest,
            _view(nonce_p, nonce_m, mac, phone, _cb("compare-other")),
        ),
        (
            "manual-pairing-sas-compare-swapped-nonce",
            "Different real nonces on the two legs make the codes differ.",
            honest,
            _view(_nonce("compare-phone-other"), nonce_m, mac, phone, cb),
        ),
    ]
    vectors = [_compare_vector(i, d, p, m, _sas_of(p), _sas_of(m)) for i, d, p, m in cases]
    assert [("expected" in v) for v in vectors] == [True, False, False, False]
    return vectors


def _sequence_vector(vector_id: str, description: str, steps: list[tuple[str, str]]) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "id": vector_id,
        "description": description,
        "input": {"kind": "sequence", "messages": [{"from": sender, "type": kind} for sender, kind in steps]},
    }
    if steps == VALID_SEQUENCE:
        entry["expected"] = {"complete": True}
    else:
        entry["expectedError"] = "outOfOrder"
        entry["closeCode"] = "PAIRING_FAILED"
    return entry


def _sequence_vectors() -> list[dict[str, Any]]:
    valid = VALID_SEQUENCE
    cases = [
        ("manual-pairing-sequence-valid", "Phone commits, Mac commits, phone reveals, Mac reveals, Mac confirms.", valid),
        (
            "manual-pairing-sequence-reveal-before-peer-commitment",
            "The phone reveals before the Mac's Commitment arrived.",
            [valid[0], ("phone", "reveal")],
        ),
        (
            "manual-pairing-sequence-mac-first",
            "The Mac sends its Commitment before the phone's.",
            [("mac", "commitment")],
        ),
        (
            "manual-pairing-sequence-mac-reveals-first",
            "The Mac reveals before the phone's Reveal was verified.",
            [valid[0], valid[1], ("mac", "reveal")],
        ),
        (
            "manual-pairing-sequence-duplicate-commitment",
            "The phone sends a second Commitment.",
            [valid[0], ("phone", "commitment")],
        ),
        (
            "manual-pairing-sequence-result-before-reveals",
            "ManualPairResult arrives before both Reveals.",
            [valid[0], valid[1], ("mac", "manualPairResult")],
        ),
        (
            "manual-pairing-sequence-qr-pair-request",
            "A QR PairRequest on a manual window is a wrong payload.",
            [("phone", "pairRequest")],
        ),
    ]
    return [_sequence_vector(i, d, s) for i, d, s in cases]


def generate_manual_pairing_vectors() -> dict[str, Any]:
    """Generates manual-pairing message, SAS, commitment, SAS-compare and ordering vectors."""

    return {
        "$schema": "./schema.json",
        "category": "manual-pairing",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": (
            _message_vectors()
            + _sas_vectors()
            + _commitment_vectors()
            + _compare_vectors()
            + _sequence_vectors()
        ),
    }
