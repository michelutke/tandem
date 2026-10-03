"""Generator for protocol/vectors/focus-encoding.json (E72-04).

Covers encode/decode vectors for the message types of docs/protocol/SPEC.md #focus-sync:

    FocusState { on (bool, 1) } (focus.proto; Envelope.payload field 120)
    FocusSyncCapability { available (bool, 1) } (focus.proto; Envelope.payload field 121)

Entries are the raw serialized message bytes for one message type at a time; `input.kind` selects
the message type (`focusState`/`focusSyncCapability`, both with `input.messageHex`).
"""

from __future__ import annotations

import hashlib
from typing import Any


def _field_bool(field_number: int, value: bool) -> bytes:
    """Encodes a bool field (omitted entirely when false, matching proto3 default-value elision)."""
    if not value:
        return b""
    return bytes([(field_number << 3) | 0, 1])


def encode_focus_state(*, on: bool) -> bytes:
    """Encodes a FocusState message body."""
    return _field_bool(1, on)


def encode_focus_sync_capability(*, available: bool) -> bytes:
    """Encodes a FocusSyncCapability message body."""
    return _field_bool(1, available)


def _vector(slug: str, description: str, kind: str, message: bytes, flag: bool) -> dict[str, Any]:
    return {
        "id": slug,
        "description": description,
        "input": {"kind": kind, "messageHex": message.hex()},
        "expected": {"flag": flag, "messageSha256": hashlib.sha256(message).hexdigest()},
    }


def generate_focus_encoding_vectors() -> dict[str, Any]:
    """Generates focus-sync message encode/decode vectors."""

    vectors: list[dict[str, Any]] = [
        _vector(
            "focus-state-on-round-trip",
            (
                "FocusState { on: true } decoding to on = true on both codecs and re-encoding to "
                "the same golden bytes (docs/protocol/SPEC.md #focus-sync)."
            ),
            "focusState",
            encode_focus_state(on=True),
            True,
        ),
        _vector(
            "focus-state-off-round-trip",
            (
                "FocusState { on: false }, an empty message under proto3 default elision, decoding "
                "to on = false on both codecs and re-encoding to the same golden (zero-length) "
                "bytes (docs/protocol/SPEC.md #focus-sync)."
            ),
            "focusState",
            encode_focus_state(on=False),
            False,
        ),
        _vector(
            "focus-sync-capability-unavailable-round-trip",
            (
                "FocusSyncCapability { available: false } decoding to available = false on both "
                "codecs and re-encoding to the same golden (zero-length) bytes "
                "(docs/protocol/SPEC.md #focus-sync)."
            ),
            "focusSyncCapability",
            encode_focus_sync_capability(available=False),
            False,
        ),
        _vector(
            "focus-sync-capability-available-round-trip",
            (
                "FocusSyncCapability { available: true } decoding to available = true on both "
                "codecs and re-encoding to the same golden bytes (docs/protocol/SPEC.md "
                "#focus-sync)."
            ),
            "focusSyncCapability",
            encode_focus_sync_capability(available=True),
            True,
        ),
    ]

    return {
        "$schema": "./schema.json",
        "category": "focus-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
