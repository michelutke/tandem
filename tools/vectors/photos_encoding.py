"""Generator for protocol/vectors/photos-encoding.json (E41-01).

Covers encode/decode vectors for the message types defined in
protocol/proto/tandem/v1/photos.proto (docs/protocol/SPEC.md #files-channel "Photos"):

    PhotoPageResult { items (repeated PhotoMeta, 1), next_cursor (string, 2),
                       access (enum PhotoAccess, 3) }
      PhotoMeta { id (string, 1), taken_at (int64, 2), width (uint32, 3), height (uint32, 4) }
    ThumbResult { id (string, 1), png_bytes (bytes, 2) }
    OriginalRequest { id (string, 1), transfer_id (string, 2) }
    PhotoError { kind (enum PhotoErrorKind, 1), ref (string, 2), reason (enum PhotoErrorReason, 3) }

PhotoAccess values: PHOTO_ACCESS_UNSPECIFIED=0, FULL=1, PARTIAL=2, NONE=3.
PhotoErrorKind values: PHOTO_ERROR_KIND_UNSPECIFIED=0, PAGE=1, THUMB=2, ORIGINAL=3.
PhotoErrorReason values: PHOTO_ERROR_REASON_UNSPECIFIED=0, NOT_FOUND=1, ACCESS_DENIED=2,
INVALID_CURSOR=3, BUSY=4.

Like files-encoding.json, these vectors are the raw serialized message bytes for one message type
at a time, not a full `Envelope` frame. Each vector's `input.kind` selects which message type
`input.messageHex` decodes as.
"""

from __future__ import annotations

import hashlib
from typing import Any

PHOTO_ACCESS = {
    "PHOTO_ACCESS_UNSPECIFIED": 0,
    "PHOTO_ACCESS_FULL": 1,
    "PHOTO_ACCESS_PARTIAL": 2,
    "PHOTO_ACCESS_NONE": 3,
}

PHOTO_ERROR_KINDS = {
    "PHOTO_ERROR_KIND_UNSPECIFIED": 0,
    "PHOTO_ERROR_KIND_PAGE": 1,
    "PHOTO_ERROR_KIND_THUMB": 2,
    "PHOTO_ERROR_KIND_ORIGINAL": 3,
}

PHOTO_ERROR_REASONS = [
    ("PHOTO_ERROR_REASON_NOT_FOUND", 1),
    ("PHOTO_ERROR_REASON_ACCESS_DENIED", 2),
    ("PHOTO_ERROR_REASON_INVALID_CURSOR", 3),
    ("PHOTO_ERROR_REASON_BUSY", 4),
]


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
    """Encodes a varint field (omitted entirely when 0, matching proto3 default-value elision)."""
    if not value:
        return b""
    return _tag(field_number, 0) + _varint(value)


def _field_int64(field_number: int, value: int) -> bytes:
    """Encodes a non-negative int64 field as a plain varint (proto3 `int64` wire format is a
    plain, non-zigzag varint; taken_at is always a non-negative Unix epoch value here)."""
    if value < 0:
        raise ValueError("taken_at fixtures must be non-negative")
    return _field_varint(field_number, value)


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


def encode_photo_meta(*, id_: str, taken_at: int, width: int, height: int) -> bytes:
    """Encodes a PhotoMeta message body."""
    parts = [_field_string(1, id_), _field_int64(2, taken_at)]
    parts.append(_field_varint(3, width))
    parts.append(_field_varint(4, height))
    return b"".join(parts)


def encode_photo_page_result(
    *, items: list[bytes], next_cursor: str, access: int
) -> bytes:
    """Encodes a PhotoPageResult message body."""
    parts = [_field_len_delimited(1, item) for item in items]
    parts.append(_field_string(2, next_cursor))
    parts.append(_field_varint(3, access))
    return b"".join(parts)


def encode_thumb_result(*, id_: str, png_bytes: bytes) -> bytes:
    """Encodes a ThumbResult message body."""
    return _field_string(1, id_) + _field_bytes(2, png_bytes)


def encode_original_request(*, id_: str, transfer_id: str) -> bytes:
    """Encodes an OriginalRequest message body."""
    return _field_string(1, id_) + _field_string(2, transfer_id)


def encode_photo_error(*, kind: int, ref: str, reason: int) -> bytes:
    """Encodes a PhotoError message body."""
    return _field_varint(1, kind) + _field_string(2, ref) + _field_varint(3, reason)


# Minimal valid 1x1 PNG, used as the ThumbResult.png_bytes fixture below (real PNG magic + IHDR/
# IDAT/IEND chunks, not just arbitrary bytes, so a receiver's "is this a PNG" sniff would pass).
_MINIMAL_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d494844520000000100000001080600000"
    "01f15c4890000000a4944415478da6360000002000155273de5000000"
    "0049454e44ae426082"
)


def generate_photos_encoding_vectors() -> dict[str, Any]:
    """Generates FILES-channel Photos (E41-01) message encode/decode vectors."""

    photo_meta_1 = encode_photo_meta(id_="photo-0001", taken_at=1_700_000_000, width=4032, height=3024)
    photo_meta_2 = encode_photo_meta(id_="photo-0002", taken_at=1_700_000_500, width=3024, height=4032)
    page_result_message = encode_photo_page_result(
        items=[photo_meta_1, photo_meta_2],
        next_cursor="cursor-page-0002",
        access=PHOTO_ACCESS["PHOTO_ACCESS_PARTIAL"],
    )

    thumb_message = encode_thumb_result(id_="photo-0001", png_bytes=_MINIMAL_PNG)

    original_request_message = encode_original_request(id_="photo-0001", transfer_id="xfer-photo-0001")

    vectors: list[dict[str, Any]] = [
        {
            "id": "photos-page-result-partial-access",
            "description": (
                "A PhotoPageResult with access PARTIAL, decoding to identical fields on both "
                "codecs (docs/protocol/SPEC.md #files-channel \"Photos\")."
            ),
            "input": {
                "kind": "photoPageResult",
                "messageHex": page_result_message.hex(),
            },
            "expected": {
                "items": [
                    {"id": "photo-0001", "takenAt": 1_700_000_000, "width": 4032, "height": 3024},
                    {"id": "photo-0002", "takenAt": 1_700_000_500, "width": 3024, "height": 4032},
                ],
                "nextCursor": "cursor-page-0002",
                "access": "PHOTO_ACCESS_PARTIAL",
            },
        },
        {
            "id": "photos-thumb-result-valid",
            "description": (
                "A ThumbResult whose png_bytes decodes to identical bytes on both codecs "
                "(docs/protocol/SPEC.md #files-channel \"Photos\")."
            ),
            "input": {
                "kind": "thumbResult",
                "messageHex": thumb_message.hex(),
            },
            "expected": {
                "id": "photo-0001",
                "pngBytesHex": _MINIMAL_PNG.hex(),
                "pngBytesSha256": hashlib.sha256(_MINIMAL_PNG).hexdigest(),
            },
        },
        {
            "id": "photos-original-request-valid",
            "description": (
                "An OriginalRequest whose transfer_id decodes exactly (docs/protocol/SPEC.md "
                "#files-channel \"Photos\" -- the phone answers with a files.proto FileOffer "
                "whose id equals transfer_id)."
            ),
            "input": {
                "kind": "originalRequest",
                "messageHex": original_request_message.hex(),
            },
            "expected": {
                "id": "photo-0001",
                "transferId": "xfer-photo-0001",
            },
        },
    ]

    for reason_name, reason_value in PHOTO_ERROR_REASONS:
        kind_name, kind_value = "PHOTO_ERROR_KIND_THUMB", PHOTO_ERROR_KINDS["PHOTO_ERROR_KIND_THUMB"]
        error_ref = f"photo-error-{reason_value:02d}"
        error_message = encode_photo_error(kind=kind_value, ref=error_ref, reason=reason_value)
        vectors.append(
            {
                "id": f"photos-error-{reason_name.lower().replace('photo_error_reason_', '').replace('_', '-')}",
                "description": (
                    f"A PhotoError with reason {reason_name}, round-tripping identically on both "
                    "codecs (docs/protocol/SPEC.md #files-channel \"Photos\")."
                ),
                "input": {
                    "kind": "photoError",
                    "messageHex": error_message.hex(),
                },
                "expected": {
                    "kind": kind_name,
                    "ref": error_ref,
                    "reason": reason_name,
                },
            }
        )

    return {
        "$schema": "./schema.json",
        "category": "photos-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
