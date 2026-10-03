"""Generator for protocol/vectors/sms-encoding.json (E50-01).

Covers encode/decode vectors for the message types defined in
protocol/proto/tandem/v1/sms.proto (docs/protocol/SPEC.md #sms-channel):

    SmsThread { thread_id (uint64, 1), address (string, 2), snippet (string, 3),
                last_message_at_ms (uint64, 4), unread_count (uint32, 5) }
    SmsMessage { id (uint64, 1), thread_id (uint64, 2), address (string, 3), body (string, 4),
                 timestamp_ms (uint64, 5), type (enum SmsMessageType, 6),
                 subscription_id (int32, 7), delivery_status (enum SmsDeliveryStatus, 8) }
    SmsSyncResponse { status (enum SmsSyncStatus, 1), threads (repeated SmsThread, 2),
                      messages (repeated SmsMessage, 3), high_watermark_id (uint64, 4),
                      backfill_cursor_id (uint64, 5), backfill_complete (bool, 6) }
    SendSmsStatus { client_message_id (string, 1), state (enum SendSmsState, 2),
                    error_code (enum SendSmsErrorCode, 3), provider_message_id (uint64, 4) }

Like contacts-encoding.json, entries are the raw serialized message bytes for one message type at a
time (`input.messageHex`); `input.kind` selects the message type (`smsMessage`/`sendSmsStatus`/
`smsSyncResponse`). The `smsEnvelopeFrame` kind instead carries a frame's 4-byte length prefix
(`input.frameHex`) and is run through each platform's real frame decoder: an SMS envelope whose
body pushes the frame past the 1 MiB maximum (docs/protocol/SPEC.md #framing-and-envelope) is
rejected from the prefix alone, before any payload buffer is allocated.
"""

from __future__ import annotations

import hashlib
from typing import Any

MAX_ENVELOPE_BYTES = 1_048_576  # 1 MiB, 2^20 (docs/protocol/SPEC.md #framing-and-envelope)

SMS_MESSAGE_TYPES = {
    "SMS_MESSAGE_TYPE_UNSPECIFIED": 0,
    "SMS_MESSAGE_TYPE_INBOX": 1,
    "SMS_MESSAGE_TYPE_SENT": 2,
    "SMS_MESSAGE_TYPE_DRAFT": 3,
    "SMS_MESSAGE_TYPE_OUTBOX": 4,
    "SMS_MESSAGE_TYPE_FAILED": 5,
    "SMS_MESSAGE_TYPE_QUEUED": 6,
}

SMS_DELIVERY_STATUSES = {
    "SMS_DELIVERY_STATUS_UNSPECIFIED": 0,
    "SMS_DELIVERY_STATUS_PENDING": 1,
    "SMS_DELIVERY_STATUS_COMPLETE": 2,
    "SMS_DELIVERY_STATUS_FAILED": 3,
}

SMS_SYNC_STATUSES = {
    "SMS_SYNC_STATUS_UNSPECIFIED": 0,
    "SMS_SYNC_STATUS_OK": 1,
    "SMS_SYNC_STATUS_PERMISSION_REQUIRED": 2,
}

SEND_SMS_STATES = {
    "SEND_SMS_STATE_UNSPECIFIED": 0,
    "SEND_SMS_STATE_SENDING": 1,
    "SEND_SMS_STATE_SENT": 2,
    "SEND_SMS_STATE_DELIVERED": 3,
    "SEND_SMS_STATE_FAILED": 4,
}

SEND_SMS_ERROR_CODES = {
    "SEND_SMS_ERROR_CODE_UNSPECIFIED": 0,
    "SEND_SMS_ERROR_CODE_GENERIC_FAILURE": 1,
    "SEND_SMS_ERROR_CODE_NO_SERVICE": 2,
    "SEND_SMS_ERROR_CODE_RADIO_OFF": 3,
    "SEND_SMS_ERROR_CODE_PERMISSION_REQUIRED": 4,
    "SEND_SMS_ERROR_CODE_INVALID_ADDRESS": 5,
    "SEND_SMS_ERROR_CODE_TOO_LONG": 6,
    "SEND_SMS_ERROR_CODE_RATE_LIMITED": 7,
    "SEND_SMS_ERROR_CODE_SUBSCRIPTION_REQUIRED": 8,
    "SEND_SMS_ERROR_CODE_INVALID_SUBSCRIPTION": 9,
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


def _u32_be(value: int) -> bytes:
    """Big-endian u32, the frame length prefix (docs/protocol/SPEC.md #framing-and-envelope)."""
    return value.to_bytes(4, "big")


def encode_sms_thread(
    *, thread_id: int, address: str, snippet: str, last_message_at_ms: int, unread_count: int
) -> bytes:
    """Encodes an SmsThread message body."""
    return (
        _field_varint(1, thread_id)
        + _field_string(2, address)
        + _field_string(3, snippet)
        + _field_varint(4, last_message_at_ms)
        + _field_varint(5, unread_count)
    )


def encode_sms_message(
    *,
    id_: int,
    thread_id: int,
    address: str,
    body: str,
    timestamp_ms: int,
    type_: int,
    subscription_id: int,
    delivery_status: int,
) -> bytes:
    """Encodes an SmsMessage message body."""
    return (
        _field_varint(1, id_)
        + _field_varint(2, thread_id)
        + _field_string(3, address)
        + _field_string(4, body)
        + _field_varint(5, timestamp_ms)
        + _field_varint(6, type_)
        + _field_varint(7, subscription_id)
        + _field_varint(8, delivery_status)
    )


def encode_sms_sync_response(
    *,
    status: int,
    threads: list[bytes],
    messages: list[bytes],
    high_watermark_id: int,
    backfill_cursor_id: int,
    backfill_complete: bool,
) -> bytes:
    """Encodes an SmsSyncResponse message body."""
    parts = [_field_varint(1, status)]
    for thread in threads:
        parts.append(_field_message(2, thread))
    for message in messages:
        parts.append(_field_message(3, message))
    parts.append(_field_varint(4, high_watermark_id))
    parts.append(_field_varint(5, backfill_cursor_id))
    parts.append(_field_bool(6, backfill_complete))
    return b"".join(parts)


def encode_send_sms_status(
    *, client_message_id: str, state: int, error_code: int, provider_message_id: int
) -> bytes:
    """Encodes a SendSmsStatus message body."""
    return (
        _field_string(1, client_message_id)
        + _field_varint(2, state)
        + _field_varint(3, error_code)
        + _field_varint(4, provider_message_id)
    )


CLIENT_MESSAGE_ID = "6f1c2b9e-3d7a-4c52-9a41-0b8e5d2f7a10"


def _send_status_vector(state_name: str, error_name: str, provider_message_id: int) -> dict[str, Any]:
    message = encode_send_sms_status(
        client_message_id=CLIENT_MESSAGE_ID,
        state=SEND_SMS_STATES[state_name],
        error_code=SEND_SMS_ERROR_CODES[error_name],
        provider_message_id=provider_message_id,
    )
    return {
        "id": f"sms-send-status-{state_name.removeprefix('SEND_SMS_STATE_').lower()}",
        "description": (
            f"A SendSmsStatus with state {state_name} decoding to the same enum value and "
            "echoing client_message_id on both codecs (docs/protocol/SPEC.md #sms-channel "
            "\"Send\")."
        ),
        "input": {"kind": "sendSmsStatus", "messageHex": message.hex()},
        "expected": {
            "clientMessageId": CLIENT_MESSAGE_ID,
            "state": state_name,
            "errorCode": error_name,
            "providerMessageId": provider_message_id,
        },
    }


def generate_sms_encoding_vectors() -> dict[str, Any]:
    """Generates SMS-channel message encode/decode vectors."""

    full_message = encode_sms_message(
        id_=4242,
        thread_id=17,
        address="+15550100",
        body="See you at 7 \u2014 bring the keys \U0001F511",
        timestamp_ms=1_700_000_000_000,
        type_=SMS_MESSAGE_TYPES["SMS_MESSAGE_TYPE_INBOX"],
        subscription_id=3,
        delivery_status=SMS_DELIVERY_STATUSES["SMS_DELIVERY_STATUS_COMPLETE"],
    )

    thread = encode_sms_thread(
        thread_id=17,
        address="+15550100",
        snippet="See you at 7",
        last_message_at_ms=1_700_000_000_000,
        unread_count=2,
    )
    sync_message_a = encode_sms_message(
        id_=900,
        thread_id=17,
        address="+15550100",
        body="Latest",
        timestamp_ms=1_700_000_100_000,
        type_=SMS_MESSAGE_TYPES["SMS_MESSAGE_TYPE_INBOX"],
        subscription_id=3,
        delivery_status=SMS_DELIVERY_STATUSES["SMS_DELIVERY_STATUS_UNSPECIFIED"],
    )
    sync_message_b = encode_sms_message(
        id_=899,
        thread_id=17,
        address="+15550100",
        body="Earlier",
        timestamp_ms=1_700_000_090_000,
        type_=SMS_MESSAGE_TYPES["SMS_MESSAGE_TYPE_SENT"],
        subscription_id=3,
        delivery_status=SMS_DELIVERY_STATUSES["SMS_DELIVERY_STATUS_COMPLETE"],
    )
    sync_response = encode_sms_sync_response(
        status=SMS_SYNC_STATUSES["SMS_SYNC_STATUS_OK"],
        threads=[thread],
        messages=[sync_message_a, sync_message_b],
        high_watermark_id=900,
        backfill_cursor_id=899,
        backfill_complete=False,
    )

    oversize_prefix = _u32_be(MAX_ENVELOPE_BYTES + 1)

    vectors: list[dict[str, Any]] = [
        {
            "id": "sms-message-full-record-valid",
            "description": (
                "A fully populated SmsMessage decoding to identical fields on both codecs "
                "(docs/protocol/SPEC.md #sms-channel)."
            ),
            "input": {"kind": "smsMessage", "messageHex": full_message.hex()},
            "expected": {
                "id": 4242,
                "threadId": 17,
                "address": "+15550100",
                "body": "See you at 7 \u2014 bring the keys \U0001F511",
                "timestampMs": 1_700_000_000_000,
                "type": "SMS_MESSAGE_TYPE_INBOX",
                "subscriptionId": 3,
                "deliveryStatus": "SMS_DELIVERY_STATUS_COMPLETE",
                "messageSha256": hashlib.sha256(full_message).hexdigest(),
            },
        },
        _send_status_vector("SEND_SMS_STATE_SENDING", "SEND_SMS_ERROR_CODE_UNSPECIFIED", 0),
        _send_status_vector("SEND_SMS_STATE_SENT", "SEND_SMS_ERROR_CODE_UNSPECIFIED", 4243),
        _send_status_vector("SEND_SMS_STATE_DELIVERED", "SEND_SMS_ERROR_CODE_UNSPECIFIED", 4243),
        _send_status_vector("SEND_SMS_STATE_FAILED", "SEND_SMS_ERROR_CODE_TOO_LONG", 0),
        {
            "id": "sms-sync-response-with-backfill-cursor",
            "description": (
                "An SmsSyncResponse page carrying one thread, two messages, high_watermark_id, "
                "backfill_cursor_id and backfill_complete = false, decoding identically on both "
                "codecs (docs/protocol/SPEC.md #sms-channel \"Cursors\")."
            ),
            "input": {"kind": "smsSyncResponse", "messageHex": sync_response.hex()},
            "expected": {
                "status": "SMS_SYNC_STATUS_OK",
                "threadCount": 1,
                "messageIds": [900, 899],
                "highWatermarkId": 900,
                "backfillCursorId": 899,
                "backfillComplete": False,
            },
        },
        {
            "id": "sms-envelope-body-over-max-frame-rejected",
            "description": (
                "An SMS Envelope frame whose body pushes length_prefix to 1 MiB + 1: rejected "
                "from the 4 prefix bytes alone, before any payload byte is read or buffered "
                "(docs/protocol/SPEC.md #framing-and-envelope, #sms-channel)."
            ),
            "input": {
                "kind": "smsEnvelopeFrame",
                "frameHex": oversize_prefix.hex(),
                "lengthPrefix": MAX_ENVELOPE_BYTES + 1,
            },
            "expectedError": "malformedFrame",
            "closeCode": "MALFORMED_FRAME",
            "localReason": "TOO_LARGE",
        },
    ]

    return {
        "$schema": "./schema.json",
        "category": "sms-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
