"""Generator for protocol/vectors/contacts-encoding.json (E51-01).

Covers encode/decode vectors for the message types defined in
protocol/proto/tandem/v1/contacts.proto (docs/protocol/SPEC.md #contacts-channel):

    Contact { contact_id (string, 1), display_name (string, 2),
              phone_numbers (repeated PhoneNumber, 3), emails (repeated Email, 4),
              photo_thumbnail (bytes, 5), updated_at_ms (uint64, 6) }
    Contact.PhoneNumber { number (string, 1), normalized_e164 (string, 2),
                          type (enum ContactAddressType, 3) }
    Contact.Email { address (string, 1), type (enum ContactAddressType, 2) }
    ContactsSyncRequest { since_updated_at_ms (uint64, 1) }
    ContactsSyncResponse { status (enum ContactsSyncStatus, 1), contacts (repeated Contact, 2),
                           deleted_contact_ids (repeated string, 3), watermark_ms (uint64, 4),
                           complete (bool, 5) }

Like clipboard-encoding.json/files-encoding.json, entries here are the raw serialized message
bytes for one message type at a time (`input.messageHex`, or `input.thumbnailRecipe` for the
oversized-thumbnail vector), not a full `Envelope` frame; `input.kind` selects which message type
`messageHex` decodes as (`contact`/`contactsSyncRequest`/`contactsSyncResponse`).
`Contact.photo_thumbnail`'s 32,768-byte cap (docs/protocol/SPEC.md #contacts-channel "Thumbnail
cap") is a message-level, app-enforced limit -- protobuf's `bytes` wire type has no inherent size
limit of its own -- the same pattern as `FileChunk.data`'s cap in files-encoding.json.
"""

from __future__ import annotations

import hashlib
from typing import Any

MAX_PHOTO_THUMBNAIL_BYTES = 32_768  # 32 KiB, 2^15 (docs/protocol/SPEC.md #contacts-channel)

CONTACT_ADDRESS_TYPES = {
    "CONTACT_ADDRESS_TYPE_UNSPECIFIED": 0,
    "CONTACT_ADDRESS_TYPE_HOME": 1,
    "CONTACT_ADDRESS_TYPE_WORK": 2,
    "CONTACT_ADDRESS_TYPE_MOBILE": 3,
    "CONTACT_ADDRESS_TYPE_OTHER": 4,
}

CONTACTS_SYNC_STATUSES = {
    "CONTACTS_SYNC_STATUS_UNSPECIFIED": 0,
    "CONTACTS_SYNC_STATUS_OK": 1,
    "CONTACTS_SYNC_STATUS_PERMISSION_REQUIRED": 2,
    "CONTACTS_SYNC_STATUS_FULL_RESYNC_REQUIRED": 3,
}


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


def _field_bool(field_number: int, value: bool) -> bytes:
    """Encodes a bool field (omitted entirely when false, matching proto3 default-value elision)."""
    return _field_varint(field_number, 1 if value else 0)


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


def _field_message(field_number: int, payload: bytes) -> bytes:
    """Encodes an embedded-message field (always emitted, even if `payload` is empty, since an
    empty message is a distinct value from an unset repeated/oneof entry)."""
    return _field_len_delimited(field_number, payload)


def encode_phone_number(*, number: str, normalized_e164: str, type_: int) -> bytes:
    """Encodes a Contact.PhoneNumber message body."""
    parts = [_field_string(1, number), _field_string(2, normalized_e164)]
    parts.append(_field_varint(3, type_))
    return b"".join(parts)


def encode_email(*, address: str, type_: int) -> bytes:
    """Encodes a Contact.Email message body."""
    return _field_string(1, address) + _field_varint(2, type_)


def encode_contact(
    *,
    contact_id: str,
    display_name: str,
    phone_numbers: list[bytes],
    emails: list[bytes],
    photo_thumbnail: bytes,
    updated_at_ms: int,
) -> bytes:
    """Encodes a Contact message body."""
    parts = [_field_string(1, contact_id), _field_string(2, display_name)]
    for phone_number in phone_numbers:
        parts.append(_field_message(3, phone_number))
    for email in emails:
        parts.append(_field_message(4, email))
    parts.append(_field_bytes(5, photo_thumbnail))
    parts.append(_field_varint(6, updated_at_ms))
    return b"".join(parts)


def encode_contacts_sync_request(*, since_updated_at_ms: int) -> bytes:
    """Encodes a ContactsSyncRequest message body."""
    return _field_varint(1, since_updated_at_ms)


def encode_contacts_sync_response(
    *,
    status: int,
    contacts: list[bytes],
    deleted_contact_ids: list[str],
    watermark_ms: int,
    complete: bool,
) -> bytes:
    """Encodes a ContactsSyncResponse message body."""
    parts = [_field_varint(1, status)]
    for contact in contacts:
        parts.append(_field_message(2, contact))
    for deleted_id in deleted_contact_ids:
        parts.append(_field_string(3, deleted_id))
    parts.append(_field_varint(4, watermark_ms))
    parts.append(_field_bool(5, complete))
    return b"".join(parts)


def generate_contacts_encoding_vectors() -> dict[str, Any]:
    """Generates CONTACTS-channel message encode/decode vectors."""

    phone_home = encode_phone_number(
        number="+1 555-0100",
        normalized_e164="+15550100",
        type_=CONTACT_ADDRESS_TYPES["CONTACT_ADDRESS_TYPE_HOME"],
    )
    phone_mobile = encode_phone_number(
        number="555.0101",
        normalized_e164="+15550101",
        type_=CONTACT_ADDRESS_TYPES["CONTACT_ADDRESS_TYPE_MOBILE"],
    )
    email_work = encode_email(
        address="ada@example.com",
        type_=CONTACT_ADDRESS_TYPES["CONTACT_ADDRESS_TYPE_WORK"],
    )
    photo_thumbnail = hashlib.sha256(b"tandem-contact-thumbnail-fixture").digest() * 8  # 256 bytes
    full_contact_message = encode_contact(
        contact_id="contact-0001",
        display_name="Ada Lovelace",
        phone_numbers=[phone_home, phone_mobile],
        emails=[email_work],
        photo_thumbnail=photo_thumbnail,
        updated_at_ms=1_700_000_000_000,
    )

    sync_request_message = encode_contacts_sync_request(since_updated_at_ms=1_699_999_000_000)

    deleted_ids = ["contact-0010", "contact-0011", "contact-0012"]
    sync_response_message = encode_contacts_sync_response(
        status=CONTACTS_SYNC_STATUSES["CONTACTS_SYNC_STATUS_OK"],
        contacts=[],
        deleted_contact_ids=deleted_ids,
        watermark_ms=1_700_000_100_000,
        complete=True,
    )

    over_fill_byte = "61"
    over_length = MAX_PHOTO_THUMBNAIL_BYTES + 1

    vectors: list[dict[str, Any]] = [
        {
            "id": "contacts-contact-full-record-valid",
            "description": (
                "A Contact with two phone numbers, one email and a photo_thumbnail, decoding to "
                "identical fields on both codecs (docs/protocol/SPEC.md #contacts-channel "
                "\"Sync\")."
            ),
            "input": {
                "kind": "contact",
                "messageHex": full_contact_message.hex(),
            },
            "expected": {
                "contactId": "contact-0001",
                "displayName": "Ada Lovelace",
                "phoneNumbers": [
                    {"number": "+1 555-0100", "normalizedE164": "+15550100", "type": "CONTACT_ADDRESS_TYPE_HOME"},
                    {"number": "555.0101", "normalizedE164": "+15550101", "type": "CONTACT_ADDRESS_TYPE_MOBILE"},
                ],
                "emails": [
                    {"address": "ada@example.com", "type": "CONTACT_ADDRESS_TYPE_WORK"},
                ],
                "photoThumbnailHex": photo_thumbnail.hex(),
                "updatedAtMs": 1_700_000_000_000,
                "contactSha256": hashlib.sha256(full_contact_message).hexdigest(),
            },
        },
        {
            "id": "contacts-sync-request-valid",
            "description": (
                "A ContactsSyncRequest whose since_updated_at_ms decodes exactly "
                "(docs/protocol/SPEC.md #contacts-channel \"Watermark\")."
            ),
            "input": {
                "kind": "contactsSyncRequest",
                "messageHex": sync_request_message.hex(),
            },
            "expected": {
                "sinceUpdatedAtMs": 1_699_999_000_000,
            },
        },
        {
            "id": "contacts-sync-response-three-deleted-ids",
            "description": (
                "A ContactsSyncResponse with three deleted_contact_ids (tombstones) and no "
                "contacts, decoding identically on both codecs (docs/protocol/SPEC.md "
                "#contacts-channel \"Sync\")."
            ),
            "input": {
                "kind": "contactsSyncResponse",
                "messageHex": sync_response_message.hex(),
            },
            "expected": {
                "status": "CONTACTS_SYNC_STATUS_OK",
                "contactCount": 0,
                "deletedContactIds": deleted_ids,
                "watermarkMs": 1_700_000_100_000,
                "complete": True,
            },
        },
        {
            "id": "contacts-contact-thumbnail-over-32kib-oversized",
            "description": (
                "Contact.photo_thumbnail one byte past the 32,768-byte (32 KiB) cap "
                "(docs/protocol/SPEC.md #contacts-channel \"Thumbnail cap\"): MUST be rejected by "
                "both platforms' validators, not truncated."
            ),
            "input": {
                "kind": "contact",
                "thumbnailRecipe": {
                    "fillByte": over_fill_byte,
                    "fillLength": over_length,
                },
            },
            "expectedError": "contactPhotoThumbnailTooLarge",
        },
    ]

    return {
        "$schema": "./schema.json",
        "category": "contacts-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
