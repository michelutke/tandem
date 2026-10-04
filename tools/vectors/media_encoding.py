"""Generator for protocol/vectors/media-encoding.json (E60-01).

Covers encode/decode vectors for the message types of docs/protocol/SPEC.md #media-ticket:

    RequestMediaTicket {} (media.proto; empty message, Envelope.payload field 8)
    MediaTicketGrant { ticket (bytes, 1), expires_at (int64, 2) } (control.proto, E01-12)
    MediaHello { ticket (bytes, 1) } (media.proto; first frame on the media connection)
    MirrorRequest {} and MirrorDeclined {} (media.proto, E61-15; empty messages, Envelope.payload
    fields 140 and 141, docs/protocol/SPEC.md #mirror-request)

Entries are the raw serialized message bytes for one message type at a time; `input.kind` selects
the message type (`requestMediaTicket`/`mediaTicketGrant`/`mediaHello`/`mirrorRequest`/`mirrorDeclined`, all with `input.messageHex`).
A `mediaHello` entry with `expectedError` is a MediaHello whose `ticket` is absent or not exactly
32 bytes: both parsers MUST reject it (TICKET_REJECTED, local reason MISSING) from the decoded
message alone, before any further frame is read.
"""

from __future__ import annotations

import hashlib
from typing import Any

TICKET_LENGTH = 32
ISSUED_AT_MS = 1_700_000_000_000
TICKET_LIFETIME_MS = 30_000


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


def _field_bytes(field_number: int, value: bytes) -> bytes:
    """Encodes a bytes field (empty value omitted, matching proto3 default-value elision)."""
    if not value:
        return b""
    return _tag(field_number, 2) + _varint(len(value)) + value


def encode_request_media_ticket() -> bytes:
    """Encodes a RequestMediaTicket message body (no fields)."""
    return b""


def encode_mirror_request() -> bytes:
    """Encodes a MirrorRequest message body (no fields)."""
    return b""


def encode_mirror_declined() -> bytes:
    """Encodes a MirrorDeclined message body (no fields)."""
    return b""


def encode_media_ticket_grant(*, ticket: bytes, expires_at: int) -> bytes:
    """Encodes a MediaTicketGrant message body."""
    return _field_bytes(1, ticket) + _field_varint(2, expires_at)


def encode_media_hello(*, ticket: bytes) -> bytes:
    """Encodes a MediaHello message body."""
    return _field_bytes(1, ticket)


def _ticket(length: int) -> bytes:
    """Deterministic fixed ticket bytes of the given length (golden test data, never a secret)."""
    seed = b"tandem-media-ticket-vector"
    return (hashlib.sha256(seed).digest() * 2)[:length]


def _hello_error_vector(slug: str, description: str, ticket: bytes) -> dict[str, Any]:
    return {
        "id": f"media-hello-{slug}",
        "description": description,
        "input": {"kind": "mediaHello", "messageHex": encode_media_hello(ticket=ticket).hex()},
        "expectedError": "ticketRejected",
        "closeCode": "TICKET_REJECTED",
        "localReason": "MISSING",
    }


def _empty_message_vector(
    slug: str, kind: str, name: str, message: bytes
) -> dict[str, Any]:
    return {
        "id": slug,
        "description": (
            f"{name}, an empty message, decoding on both codecs and re-encoding to the same golden "
            "(zero-length) bytes (docs/protocol/SPEC.md #mirror-request)."
        ),
        "input": {"kind": kind, "messageHex": message.hex()},
        "expected": {"messageSha256": hashlib.sha256(message).hexdigest()},
    }


def generate_media_encoding_vectors() -> dict[str, Any]:
    """Generates media-ticket message encode/decode vectors."""

    ticket = _ticket(TICKET_LENGTH)
    request = encode_request_media_ticket()
    grant = encode_media_ticket_grant(ticket=ticket, expires_at=ISSUED_AT_MS + TICKET_LIFETIME_MS)
    hello = encode_media_hello(ticket=ticket)

    vectors: list[dict[str, Any]] = [
        {
            "id": "request-media-ticket-round-trip",
            "description": (
                "RequestMediaTicket, an empty message, decoding on both codecs and re-encoding to "
                "the same golden (zero-length) bytes (docs/protocol/SPEC.md #media-ticket)."
            ),
            "input": {"kind": "requestMediaTicket", "messageHex": request.hex()},
            "expected": {"messageSha256": hashlib.sha256(request).hexdigest()},
        },
        {
            "id": "media-ticket-grant-round-trip",
            "description": (
                "MediaTicketGrant with a 32-byte ticket and expiresAt 30 s after issuance decoding "
                "to identical fields on both codecs and re-encoding to the same golden bytes "
                "(docs/protocol/SPEC.md #media-ticket \"Issuance\")."
            ),
            "input": {"kind": "mediaTicketGrant", "messageHex": grant.hex()},
            "expected": {
                "ticketHex": ticket.hex(),
                "expiresAt": ISSUED_AT_MS + TICKET_LIFETIME_MS,
                "messageSha256": hashlib.sha256(grant).hexdigest(),
            },
        },
        {
            "id": "media-hello-round-trip",
            "description": (
                "MediaHello with a 32-byte ticket decoding to the same ticket on both codecs and "
                "re-encoding to the same golden bytes (docs/protocol/SPEC.md #media-ticket "
                "\"Consumption and single use\")."
            ),
            "input": {"kind": "mediaHello", "messageHex": hello.hex()},
            "expected": {
                "ticketHex": ticket.hex(),
                "messageSha256": hashlib.sha256(hello).hexdigest(),
            },
        },
        _empty_message_vector(
            "mirror-request-round-trip", "mirrorRequest", "MirrorRequest", encode_mirror_request()
        ),
        _empty_message_vector(
            "mirror-declined-round-trip", "mirrorDeclined", "MirrorDeclined", encode_mirror_declined()
        ),
        _hello_error_vector(
            "missing-ticket-field",
            (
                "A MediaHello with no ticket field (empty message) MUST be rejected "
                "TICKET_REJECTED/MISSING by both parsers before any further frame is read "
                "(docs/protocol/SPEC.md #media-ticket, case 0)."
            ),
            b"",
        ),
        _hello_error_vector(
            "ticket-31-bytes",
            (
                "A MediaHello whose ticket is 31 bytes (one short) MUST be rejected "
                "TICKET_REJECTED/MISSING by both parsers (docs/protocol/SPEC.md #media-ticket, "
                "case 0)."
            ),
            _ticket(TICKET_LENGTH - 1),
        ),
        _hello_error_vector(
            "ticket-33-bytes",
            (
                "A MediaHello whose ticket is 33 bytes (one over) MUST be rejected "
                "TICKET_REJECTED/MISSING by both parsers (docs/protocol/SPEC.md #media-ticket, "
                "case 0)."
            ),
            _ticket(TICKET_LENGTH + 1),
        ),
    ]

    return {
        "$schema": "./schema.json",
        "category": "media-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
