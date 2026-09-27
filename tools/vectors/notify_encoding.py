"""Generator for protocol/vectors/notify-encoding.json (E30-01).

Covers frame-level encode/decode round-trip vectors for NOTIFY channel payloads:
NotificationPosted, IconData, NotificationAction, NotificationDismiss, and
NotificationActionResult messages defined in protocol/proto/tandem/v1/notify.proto. Each vector is
a complete Envelope frame (length_prefix + envelope_bytes) that should encode and decode
identically, exercising codec round-trip (like status_encoding.py for the STATUS channel).

NotificationPosted fields: key (string, 1), package_name (string, 2), app_version_code (int64, 3),
  title (string, 4), text (string, 5), messaging_style_senders (repeated string, 6),
  visibility (enum, 7), has_icon (bool, 8)
IconData fields: package_name (string, 1), version_code (int64, 2), png_bytes (bytes, 3)
NotificationAction fields: key (string, 1), action_index (int32, 2), reply_text (string, 3)
NotificationDismiss fields: key (string, 1), origin (enum Origin, 2),
  values ORIGIN_UNSPECIFIED=0, ORIGIN_ANDROID=1, ORIGIN_MACOS=2
NotificationActionResult fields: key (string, 1), status (enum Status, 2),
  values STATUS_UNSPECIFIED=0, STATUS_OK=1, STATUS_GONE=2, STATUS_FAILED=3
"""

from __future__ import annotations

from typing import Any


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


def encode_notification_posted(
    *,
    key: str,
    package_name: str,
    app_version_code: int,
    title: str,
    text: str,
    messaging_style_senders: list[str],
    visibility: int,
    has_icon: bool,
) -> bytes:
    """Encodes a NotificationPosted message (field 30 in envelope)."""
    parts = [
        _field_string(1, key),
        _field_string(2, package_name),
    ]
    if app_version_code:
        parts.append(_field_varint(3, app_version_code))
    parts.append(_field_string(4, title))
    parts.append(_field_string(5, text))
    for sender in messaging_style_senders:
        parts.append(_field_string(6, sender))
    if visibility:
        parts.append(_field_varint(7, visibility))
    if has_icon:
        parts.append(_field_varint(8, 1))
    return _field_len_delimited(30, b"".join(parts))


def encode_icon_data(*, package_name: str, version_code: int, png_bytes: bytes) -> bytes:
    """Encodes an IconData message (field 31 in envelope)."""
    parts = [_field_string(1, package_name)]
    if version_code:
        parts.append(_field_varint(2, version_code))
    parts.append(_field_bytes(3, png_bytes))
    return _field_len_delimited(31, b"".join(parts))


def encode_notification_action(*, key: str, action_index: int, reply_text: str) -> bytes:
    """Encodes a NotificationAction message (field 32 in envelope)."""
    parts = [_field_string(1, key)]
    if action_index:
        parts.append(_field_varint(2, action_index))
    parts.append(_field_string(3, reply_text))
    return _field_len_delimited(32, b"".join(parts))


def encode_notification_dismiss(*, key: str, origin: int) -> bytes:
    """Encodes a NotificationDismiss message (field 33 in envelope)."""
    parts = [_field_string(1, key)]
    if origin:
        parts.append(_field_varint(2, origin))
    return _field_len_delimited(33, b"".join(parts))


def encode_notification_action_result(*, key: str, status: int) -> bytes:
    """Encodes a NotificationActionResult message (field 34 in envelope)."""
    parts = [_field_string(1, key)]
    if status:
        parts.append(_field_varint(2, status))
    return _field_len_delimited(34, b"".join(parts))


def build_envelope_frame(*, channel: int, seq: int, ack: int, payload: bytes) -> bytes:
    """Builds a complete Envelope frame with 4-byte big-endian length prefix."""
    envelope = b""
    envelope += _field_varint(1, channel)
    if seq:
        envelope += _field_varint(2, seq)
    if ack:
        envelope += _field_varint(3, ack)
    envelope += payload
    length_prefix = len(envelope).to_bytes(4, "big")
    return length_prefix + envelope


def generate_notify_encoding_vectors() -> dict[str, Any]:
    """Generates frame-level encode/decode round-trip vectors for the NOTIFY channel."""

    channel_notify = 2

    vectors = [
        {
            "id": "notify-notification-posted-messaging-style-three-senders",
            "description": (
                "NotificationPosted for a MessagingStyle conversation with 3 senders."
            ),
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_notify,
                    seq=1,
                    ack=0,
                    payload=encode_notification_posted(
                        key="com.example.chat|1001",
                        package_name="com.example.chat",
                        app_version_code=42,
                        title="Team Standup",
                        text="Alice: On my way\nBob: See you there\nCara: 👍",
                        messaging_style_senders=["Alice", "Bob", "Cara"],
                        visibility=1,  # VISIBILITY_PUBLIC
                        has_icon=True,
                    ),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_NOTIFY",
                "seq": 1,
                "ack": 0,
                "payload": "notificationPosted",
            },
        },
        {
            "id": "notify-notification-action-with-reply-text",
            "description": "NotificationAction for a RemoteInput-capable action with a reply.",
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_notify,
                    seq=7,
                    ack=6,
                    payload=encode_notification_action(
                        key="com.example.chat|1001",
                        action_index=1,
                        reply_text="On my way too!",
                    ),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_NOTIFY",
                "seq": 7,
                "ack": 6,
                "payload": "notificationAction",
            },
        },
        {
            "id": "notify-notification-dismiss-origin-macos",
            "description": "NotificationDismiss originating from the Mac.",
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_notify,
                    seq=8,
                    ack=7,
                    payload=encode_notification_dismiss(
                        key="com.example.chat|1001",
                        origin=2,  # ORIGIN_MACOS
                    ),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_NOTIFY",
                "seq": 8,
                "ack": 7,
                "payload": "notificationDismiss",
            },
        },
        {
            "id": "notify-icon-data-png-bytes",
            "description": "IconData carrying a small PNG payload for an app version.",
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_notify,
                    seq=2,
                    ack=1,
                    payload=encode_icon_data(
                        package_name="com.example.chat",
                        version_code=42,
                        png_bytes=bytes.fromhex(
                            "89504e470d0a1a0a0000000d49484452"
                            "0000000100000001080600000037"
                        ),
                    ),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_NOTIFY",
                "seq": 2,
                "ack": 1,
                "payload": "iconData",
            },
        },
        {
            "id": "notify-notification-action-result-status-gone",
            "description": (
                "NotificationActionResult reporting that the source notification was already "
                "gone (UC-09 alternate)."
            ),
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_notify,
                    seq=9,
                    ack=8,
                    payload=encode_notification_action_result(
                        key="com.example.chat|1001",
                        status=2,  # STATUS_GONE
                    ),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_NOTIFY",
                "seq": 9,
                "ack": 8,
                "payload": "notificationActionResult",
            },
        },
    ]

    return {
        "$schema": "./schema.json",
        "category": "notify-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
