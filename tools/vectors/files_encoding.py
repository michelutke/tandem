"""Generator for protocol/vectors/files-encoding.json (E40-01).

Covers encode/decode vectors for the message types defined in
protocol/proto/tandem/v1/files.proto (docs/protocol/SPEC.md #files-channel):

    FileOffer { id (string, 1), name (string, 2), size (uint64, 3), mime (string, 4),
                sha256 (bytes, 5) }
    FileAccept { id (string, 1) }
    FileReject { id (string, 1), reason (enum TransferReason, 2) }
    FileChunk { id (string, 1), seq (uint64, 2), offset (uint64, 3), data (bytes, 4) }
    FileResumeRequest { id (string, 1), from_offset (uint64, 2) }

TransferReason values: TRANSFER_REASON_UNSPECIFIED=0, DECLINED=1, TIMEOUT=2,
INSUFFICIENT_SPACE=3, INVALID_NAME=4, HASH_MISMATCH=5, PROTOCOL_VIOLATION=6, USER_CANCELLED=7,
UNKNOWN_TRANSFER=8, SOURCE_UNAVAILABLE=9, IO_ERROR=10, BUSY=11, TOO_LARGE=12.

Like clipboard-encoding.json (not notify-encoding.json/status-encoding.json), these vectors are
the raw serialized message bytes for one message type at a time, not a full `Envelope` frame:
`FileChunk.data`'s own 262,144-byte cap (docs/protocol/SPEC.md #files-channel "Chunking") is a
message-level, app-enforced limit -- protobuf's `bytes` wire type has no inherent size limit of
its own -- distinct from the unrelated 1 MiB `Envelope` frame-length cap `frame-encoding.json`
already covers. Each vector's `input.kind` selects which message type `input.messageHex` (or,
for the oversized chunk, `input.dataRecipe`) decodes as.
"""

from __future__ import annotations

import hashlib
from typing import Any

MAX_FILE_CHUNK_BYTES = 262_144  # 256 KiB, 2^18 (docs/protocol/SPEC.md #files-channel "Chunking")

TRANSFER_REASONS = [
    ("TRANSFER_REASON_DECLINED", 1),
    ("TRANSFER_REASON_TIMEOUT", 2),
    ("TRANSFER_REASON_INSUFFICIENT_SPACE", 3),
    ("TRANSFER_REASON_INVALID_NAME", 4),
    ("TRANSFER_REASON_HASH_MISMATCH", 5),
    ("TRANSFER_REASON_PROTOCOL_VIOLATION", 6),
    ("TRANSFER_REASON_USER_CANCELLED", 7),
    ("TRANSFER_REASON_UNKNOWN_TRANSFER", 8),
    ("TRANSFER_REASON_SOURCE_UNAVAILABLE", 9),
    ("TRANSFER_REASON_IO_ERROR", 10),
    ("TRANSFER_REASON_BUSY", 11),
    ("TRANSFER_REASON_TOO_LARGE", 12),
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


def encode_file_offer(*, id_: str, name: str, size: int, mime: str, sha256: bytes) -> bytes:
    """Encodes a FileOffer message body."""
    parts = [_field_string(1, id_), _field_string(2, name)]
    parts.append(_field_varint(3, size))
    parts.append(_field_string(4, mime))
    parts.append(_field_bytes(5, sha256))
    return b"".join(parts)


def encode_file_accept(*, id_: str) -> bytes:
    """Encodes a FileAccept message body."""
    return _field_string(1, id_)


def encode_file_reject(*, id_: str, reason: int) -> bytes:
    """Encodes a FileReject message body."""
    return _field_string(1, id_) + _field_varint(2, reason)


def encode_file_chunk(*, id_: str, seq: int, offset: int, data: bytes) -> bytes:
    """Encodes a FileChunk message body."""
    parts = [_field_string(1, id_)]
    parts.append(_field_varint(2, seq))
    parts.append(_field_varint(3, offset))
    parts.append(_field_bytes(4, data))
    return b"".join(parts)


def encode_file_resume_request(*, id_: str, from_offset: int) -> bytes:
    """Encodes a FileResumeRequest message body."""
    return _field_string(1, id_) + _field_varint(2, from_offset)


def generate_files_encoding_vectors() -> dict[str, Any]:
    """Generates FILES-channel message encode/decode vectors."""

    offer_sha256 = hashlib.sha256(b"tandem-file-offer-fixture").digest()
    offer_message = encode_file_offer(
        id_="xfer-0001",
        name="vacation-photo.jpg",
        size=4_194_304,
        mime="image/jpeg",
        sha256=offer_sha256,
    )
    accept_message = encode_file_accept(id_="xfer-0001")

    chunk_data = bytes(range(256)) * 4  # 1024 bytes, well under the cap
    chunk_message = encode_file_chunk(id_="xfer-0001", seq=3, offset=3 * 262_144, data=chunk_data)

    resume_message = encode_file_resume_request(id_="xfer-0002", from_offset=5 * 262_144)

    over_fill_byte = "61"
    over_length = MAX_FILE_CHUNK_BYTES + 1

    vectors: list[dict[str, Any]] = [
        {
            "id": "files-offer-valid",
            "description": (
                "A FileOffer decoding to identical fields on both codecs (docs/protocol/SPEC.md "
                "#files-channel \"Handshake\")."
            ),
            "input": {
                "kind": "fileOffer",
                "messageHex": offer_message.hex(),
            },
            "expected": {
                "id": "xfer-0001",
                "name": "vacation-photo.jpg",
                "size": 4_194_304,
                "mime": "image/jpeg",
                "sha256Hex": offer_sha256.hex(),
            },
        },
        {
            "id": "files-accept-valid",
            "description": (
                "A FileAccept for the offer above, decoding to identical fields on both codecs."
            ),
            "input": {
                "kind": "fileAccept",
                "messageHex": accept_message.hex(),
            },
            "expected": {
                "id": "xfer-0001",
            },
        },
        {
            "id": "files-chunk-valid",
            "description": (
                "A FileChunk within the 262,144-byte cap (docs/protocol/SPEC.md #files-channel "
                "\"Chunking\"), decoding to identical fields on both codecs."
            ),
            "input": {
                "kind": "fileChunk",
                "messageHex": chunk_message.hex(),
            },
            "expected": {
                "id": "xfer-0001",
                "seq": 3,
                "offset": 3 * 262_144,
                "dataHex": chunk_data.hex(),
                "dataByteLength": len(chunk_data),
            },
        },
        {
            "id": "files-resume-request-valid",
            "description": (
                "A FileResumeRequest whose from_offset decodes exactly (docs/protocol/SPEC.md "
                "#files-channel \"Resume\")."
            ),
            "input": {
                "kind": "fileResumeRequest",
                "messageHex": resume_message.hex(),
            },
            "expected": {
                "id": "xfer-0002",
                "fromOffset": 5 * 262_144,
            },
        },
        {
            "id": "files-chunk-262145-byte-payload-oversized",
            "description": (
                "FileChunk.data one byte past the 262,144-byte (256 KiB) cap "
                "(docs/protocol/SPEC.md #files-channel \"Chunking\"): MUST be rejected as "
                "oversized by both codecs, not truncated."
            ),
            "input": {
                "kind": "fileChunk",
                "id": "xfer-0003",
                "seq": 0,
                "offset": 0,
                "dataRecipe": {
                    "fillByte": over_fill_byte,
                    "fillLength": over_length,
                },
            },
            "expectedError": "fileChunkPayloadTooLarge",
        },
    ]

    for reason_name, reason_value in TRANSFER_REASONS:
        reject_id = f"xfer-reject-{reason_value:02d}"
        reject_message = encode_file_reject(id_=reject_id, reason=reason_value)
        vectors.append(
            {
                "id": f"files-reject-{reason_name.lower().replace('transfer_reason_', '').replace('_', '-')}",
                "description": (
                    f"A FileReject with reason {reason_name}, round-tripping identically on "
                    "both codecs (docs/protocol/SPEC.md #files-channel)."
                ),
                "input": {
                    "kind": "fileReject",
                    "messageHex": reject_message.hex(),
                },
                "expected": {
                    "id": reject_id,
                    "reason": reason_name,
                },
            }
        )

    return {
        "$schema": "./schema.json",
        "category": "files-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
