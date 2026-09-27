"""Generator for protocol/vectors/clipboard-encoding.json (E31-01).

Covers encode/decode vectors for the `ClipboardText` message defined in
protocol/proto/tandem/v1/clipboard.proto (docs/protocol/SPEC.md #clipboard-channel):

    ClipboardText { origin_tag (string, 1), content_hash (bytes, 2), text (string, 3),
                    sensitive (bool, 4) }

Unlike notify-encoding.json / status-encoding.json, these vectors are NOT wrapped in a full
`Envelope` frame: `text` can be exactly at (or one byte past) the channel's own 1,048,576-byte cap
(docs/protocol/SPEC.md #timeouts-connection-limits-and-resource-caps "Feature caps" and
#clipboard-channel), which is a message-level limit distinct from -- and, once Envelope/frame
overhead is added, smaller than -- the unrelated 1 MiB `Envelope` frame-length cap enforced by
`FrameDecoder`/`frame-encoding.json` (docs/protocol/SPEC.md #framing-and-envelope). Exercising the
`ClipboardText` cap through the real frame decoder would make the "exactly 1,048,576 bytes text is
accepted" vector self-contradictory (the wrapping `Envelope` would itself exceed the frame cap
first). Each vector's `input` is therefore the raw serialized `ClipboardText` message bytes (or,
for the two boundary vectors, a compact `textRecipe` describing them -- see the "Compact recipes
for large payloads" note in protocol/vectors/README.md), which both conformance runners decode
directly with their generated `ClipboardText` type and then validate against
MAX_CLIPBOARD_TEXT_BYTES below.
"""

from __future__ import annotations

import hashlib
from typing import Any

MAX_CLIPBOARD_TEXT_BYTES = 1_048_576  # 1 MiB, 2^20 (docs/protocol/SPEC.md #clipboard-channel)


def _varint(value: int) -> bytes:
    """Minimal protobuf varint encoder: encodes non-negative int as variable-length bytes."""
    if value < 0:
        raise ValueError("varint must be non-negative")
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def _tag(field_number: int, wire_type: int) -> bytes:
    """Encodes field tag: (field_number << 3) | wire_type as a varint."""
    return _varint((field_number << 3) | wire_type)


def _field_varint(field_number: int, value: int) -> bytes:
    """Encodes a varint field."""
    return _tag(field_number, 0) + _varint(value)


def _field_len_delimited(field_number: int, payload: bytes) -> bytes:
    """Encodes a length-delimited (message/string/bytes) field."""
    return _tag(field_number, 2) + _varint(len(payload)) + payload


def _field_string(field_number: int, value: str) -> bytes:
    """Encodes a string field (empty string omitted, matching proto3 default-value elision)."""
    if not value:
        return b""
    return _field_len_delimited(field_number, value.encode("utf-8"))


def _field_bytes(field_number: int, value: bytes) -> bytes:
    """Encodes a bytes field (empty bytes omitted, matching proto3 default-value elision)."""
    if not value:
        return b""
    return _field_len_delimited(field_number, value)


def content_hash_for(text: str) -> bytes:
    """SHA-256 digest of `text`'s UTF-8 bytes (docs/protocol/SPEC.md #clipboard-channel,
    `content_hash = SHA-256(UTF-8(text))`)."""
    return hashlib.sha256(text.encode("utf-8")).digest()


def encode_clipboard_text(*, origin_tag: str, content_hash: bytes, text: str, sensitive: bool) -> bytes:
    """Encodes a ClipboardText message body (field 40 in Envelope.payload, clipboard.proto)."""
    parts = [_field_string(1, origin_tag)]
    parts.append(_field_bytes(2, content_hash))
    parts.append(_field_string(3, text))
    if sensitive:
        parts.append(_field_varint(4, 1))
    return b"".join(parts)


def build_clipboard_text_from_recipe(recipe: dict) -> bytes:
    """Reconstructs the exact ClipboardText message bytes a manifest entry's `input` describes,
    for the two boundary vectors below whose `text` is filled compactly rather than inlined (see
    module docstring / protocol/vectors/README.md "Compact recipes for large payloads")."""
    text_recipe = recipe["textRecipe"]
    fill_byte = bytes.fromhex(text_recipe["fillByte"])
    text = (fill_byte * text_recipe["fillLength"]).decode("ascii")
    return encode_clipboard_text(
        origin_tag=recipe["originTag"],
        content_hash=bytes.fromhex(recipe["contentHashHex"]),
        text=text,
        sensitive=recipe["sensitive"],
    )


def build_clipboard_text_bytes(vector: dict) -> bytes:
    """Reconstructs the exact ClipboardText message bytes a manifest entry's `input` describes,
    whether inlined as `clipboardTextHex` or described compactly as a `textRecipe`."""
    entry_input = vector["input"]
    if "clipboardTextHex" in entry_input:
        return bytes.fromhex(entry_input["clipboardTextHex"])
    return build_clipboard_text_from_recipe(entry_input)


def generate_clipboard_encoding_vectors() -> dict[str, Any]:
    """Generates `ClipboardText` encode/decode vectors for the CLIPBOARD channel."""

    sensitive_text = "hunter2correcthorsebatterystaple"
    sensitive_hash = content_hash_for(sensitive_text)
    sensitive_message = encode_clipboard_text(
        origin_tag="android",
        content_hash=sensitive_hash,
        text=sensitive_text,
        sensitive=True,
    )

    exact_fill_byte = "61"  # ASCII 'a'
    exact_length = MAX_CLIPBOARD_TEXT_BYTES
    exact_text = bytes.fromhex(exact_fill_byte) * exact_length
    exact_hash = hashlib.sha256(exact_text).digest()
    exact_message = encode_clipboard_text(
        origin_tag="macos",
        content_hash=exact_hash,
        text=exact_text.decode("ascii"),
        sensitive=False,
    )

    over_fill_byte = "61"
    over_length = MAX_CLIPBOARD_TEXT_BYTES + 1
    over_text = bytes.fromhex(over_fill_byte) * over_length
    over_hash = hashlib.sha256(over_text).digest()

    vectors = [
        {
            "id": "clipboard-text-sensitive-true",
            "description": (
                "A sensitive ClipboardText (e.g. from a password manager), origin_tag=android, "
                "round-tripping byte-identically through both codecs."
            ),
            "input": {
                "clipboardTextHex": sensitive_message.hex(),
            },
            "expected": {
                "originTag": "android",
                "contentHashHex": sensitive_hash.hex(),
                "text": sensitive_text,
                "sensitive": True,
                "textByteLength": len(sensitive_text.encode("utf-8")),
            },
        },
        {
            "id": "clipboard-text-exactly-1-mib",
            "description": (
                "ClipboardText.text at exactly the 1,048,576-byte (1 MiB) cap "
                "(#clipboard-channel): MUST be accepted."
            ),
            "input": {
                "originTag": "macos",
                "sensitive": False,
                "contentHashHex": exact_hash.hex(),
                "textRecipe": {
                    "fillByte": exact_fill_byte,
                    "fillLength": exact_length,
                },
            },
            "expected": {
                "accepted": True,
                "originTag": "macos",
                "contentHashHex": exact_hash.hex(),
                "sensitive": False,
                "textByteLength": exact_length,
                "clipboardTextSha256": hashlib.sha256(exact_message).hexdigest(),
            },
        },
        {
            "id": "clipboard-text-one-byte-over-1-mib",
            "description": (
                "ClipboardText.text one byte past the 1,048,576-byte (1 MiB) cap "
                "(#clipboard-channel): MUST be rejected, not truncated."
            ),
            "input": {
                "originTag": "macos",
                "sensitive": False,
                "contentHashHex": over_hash.hex(),
                "textRecipe": {
                    "fillByte": over_fill_byte,
                    "fillLength": over_length,
                },
            },
            "expectedError": "clipboardTextTooLarge",
        },
    ]

    return {
        "$schema": "./schema.json",
        "category": "clipboard-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
