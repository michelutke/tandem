"""Generator for protocol/vectors/status-encoding.json (E23-01).

Covers frame-level encode/decode round-trip vectors for STATUS channel payloads:
DeviceStatus, Ring, and RingStop messages defined in protocol/proto/tandem/v1/status.proto.
Each vector is a complete Envelope frame (length_prefix + envelope_bytes) that should encode
and decode identically, exercising codec round-trip (like frame-encoding.json for other channels).

DeviceStatus fields: battery_level (int32, field 1), is_charging (bool, field 2),
  network_type (enum, field 3), signal_level (int32, field 4)
Ring: empty message (no fields)
RingStop fields: origin (enum Origin, field 1), values ORIGIN_UNSPECIFIED=0, ORIGIN_MAC=1, ORIGIN_PHONE=2
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
    """Encodes a length-delimited (message) field."""
    return _tag(field_number, 2) + _varint(len(payload)) + payload


def encode_device_status(
    *, battery_level: int, is_charging: bool, network_type: int, signal_level: int
) -> bytes:
    """Encodes a DeviceStatus message."""
    parts = []
    if battery_level != 0:
        parts.append(_field_varint(1, battery_level))
    if is_charging:
        parts.append(_field_varint(2, 1))
    if network_type != 0:
        parts.append(_field_varint(3, network_type))
    if signal_level != 0:
        parts.append(_field_varint(4, signal_level))
    return b"".join(parts)


def encode_ring() -> bytes:
    """Encodes an empty Ring message (field 21 in envelope)."""
    return _field_len_delimited(21, b"")


def encode_ring_stop(*, origin: int) -> bytes:
    """Encodes a RingStop message with the given origin enum value (field 22 in envelope)."""
    if origin == 0:  # ORIGIN_UNSPECIFIED
        content = b""
    else:
        content = _field_varint(1, origin)
    return _field_len_delimited(22, content)


def build_envelope_frame(
    *, channel: int, seq: int, ack: int, payload: bytes
) -> bytes:
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


def generate_status_encoding_vectors() -> dict[str, Any]:
    """Generates frame-level encode/decode round-trip vectors for STATUS channel."""

    channel_status = 9

    vectors = [
        # DeviceStatus vectors
        {
            "id": "status-device-status-minimal",
            "description": "Minimal DeviceStatus with all fields at proto3 defaults (omitted).",
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_status,
                    seq=1,
                    ack=0,
                    payload=_field_len_delimited(20, encode_device_status(
                        battery_level=0, is_charging=False, network_type=0, signal_level=0
                    )),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_STATUS",
                "seq": 1,
                "ack": 0,
                "payload": "deviceStatus",
            },
        },
        {
            "id": "status-device-status-typical",
            "description": "Typical DeviceStatus: 82% battery, charging, Wi-Fi, 3 bars signal.",
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_status,
                    seq=42,
                    ack=41,
                    payload=_field_len_delimited(20, encode_device_status(
                        battery_level=82, is_charging=True, network_type=1, signal_level=3
                    )),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_STATUS",
                "seq": 42,
                "ack": 41,
                "payload": "deviceStatus",
            },
        },
        {
            "id": "status-ring",
            "description": "Ring message on STATUS channel: smallest legal Ring frame.",
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_status,
                    seq=1,
                    ack=0,
                    payload=encode_ring(),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_STATUS",
                "seq": 1,
                "ack": 0,
                "payload": "ring",
            },
        },
        {
            "id": "status-ring-stop-mac",
            "description": "RingStop with origin=MAC (1) from Mac side.",
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_status,
                    seq=2,
                    ack=1,
                    payload=encode_ring_stop(origin=1),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_STATUS",
                "seq": 2,
                "ack": 1,
                "payload": "ringStop",
            },
        },
        {
            "id": "status-ring-stop-phone",
            "description": "RingStop with origin=PHONE (2) from phone side.",
            "input": {
                "frameHex": build_envelope_frame(
                    channel=channel_status,
                    seq=3,
                    ack=2,
                    payload=encode_ring_stop(origin=2),
                ).hex(),
                "lengthPrefix": 0,
                "suppliedEnvelopeLength": 0,
            },
            "expected": {
                "channel": "CHANNEL_STATUS",
                "seq": 3,
                "ack": 2,
                "payload": "ringStop",
            },
        },
    ]

    return {
        "$schema": "./schema.json",
        "category": "status-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
