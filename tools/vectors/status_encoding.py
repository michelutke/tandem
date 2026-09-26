"""Generator for protocol/vectors/status-encoding.json (E23-01).

Covers encode/decode and round-trip vectors for DeviceStatus and RingStop messages,
carried on the STATUS channel and defined in protocol/proto/tandem/v1/status.proto.

DeviceStatus fields:
  - battery_level (int32, field 1)
  - is_charging (bool, field 2)
  - network_type (enum, field 3)
  - signal_level (int32, field 4)

RingStop fields:
  - origin (enum Origin, field 1), with values ORIGIN_UNSPECIFIED=0, ORIGIN_MAC=1, ORIGIN_PHONE=2
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


def encode_ring_stop(*, origin: int) -> bytes:
    """Encodes a RingStop message with the given origin enum value."""
    if origin == 0:  # ORIGIN_UNSPECIFIED
        return b""  # empty message
    return _field_varint(1, origin)


def generate_status_encoding_vectors() -> dict[str, Any]:
    """Generates encode/decode round-trip vectors for DeviceStatus and RingStop."""

    vectors = [
        # DeviceStatus vectors
        {
            "id": "device-status-minimal",
            "description": "Minimal DeviceStatus with all fields at proto3 defaults (omitted).",
            "input": {
                "kind": "deviceStatus",
                "battery_level": 0,
                "is_charging": False,
                "network_type": 0,
                "signal_level": 0,
            },
            "expected": {
                "bytesHex": encode_device_status(
                    battery_level=0, is_charging=False, network_type=0, signal_level=0
                ).hex(),
                "battery_level": 0,
                "is_charging": False,
                "network_type": 0,
                "signal_level": 0,
            },
        },
        {
            "id": "device-status-typical",
            "description": "Typical DeviceStatus: 82% battery, charging, Wi-Fi, 3 bars signal.",
            "input": {
                "kind": "deviceStatus",
                "battery_level": 82,
                "is_charging": True,
                "network_type": 1,  # NETWORK_TYPE_WIFI
                "signal_level": 3,
            },
            "expected": {
                "bytesHex": encode_device_status(
                    battery_level=82, is_charging=True, network_type=1, signal_level=3
                ).hex(),
                "battery_level": 82,
                "is_charging": True,
                "network_type": 1,
                "signal_level": 3,
            },
        },
        {
            "id": "device-status-cellular",
            "description": "DeviceStatus with cellular network and full signal.",
            "input": {
                "kind": "deviceStatus",
                "battery_level": 100,
                "is_charging": False,
                "network_type": 2,  # NETWORK_TYPE_CELLULAR
                "signal_level": 4,
            },
            "expected": {
                "bytesHex": encode_device_status(
                    battery_level=100, is_charging=False, network_type=2, signal_level=4
                ).hex(),
                "battery_level": 100,
                "is_charging": False,
                "network_type": 2,
                "signal_level": 4,
            },
        },
        {
            "id": "device-status-offline",
            "description": "DeviceStatus with offline network (signal_level becomes meaningless, set to 0).",
            "input": {
                "kind": "deviceStatus",
                "battery_level": 15,
                "is_charging": False,
                "network_type": 3,  # NETWORK_TYPE_OFFLINE
                "signal_level": 0,
            },
            "expected": {
                "bytesHex": encode_device_status(
                    battery_level=15, is_charging=False, network_type=3, signal_level=0
                ).hex(),
                "battery_level": 15,
                "is_charging": False,
                "network_type": 3,
                "signal_level": 0,
            },
        },
        # RingStop vectors
        {
            "id": "ring-stop-unspecified",
            "description": "RingStop with origin UNSPECIFIED (0): encodes as empty message.",
            "input": {
                "kind": "ringStop",
                "origin": 0,  # ORIGIN_UNSPECIFIED
            },
            "expected": {
                "bytesHex": encode_ring_stop(origin=0).hex(),
                "origin": 0,
            },
        },
        {
            "id": "ring-stop-mac",
            "description": "RingStop from Mac side (origin=1).",
            "input": {
                "kind": "ringStop",
                "origin": 1,  # ORIGIN_MAC
            },
            "expected": {
                "bytesHex": encode_ring_stop(origin=1).hex(),
                "origin": 1,
            },
        },
        {
            "id": "ring-stop-phone",
            "description": "RingStop from phone side (origin=2).",
            "input": {
                "kind": "ringStop",
                "origin": 2,  # ORIGIN_PHONE
            },
            "expected": {
                "bytesHex": encode_ring_stop(origin=2).hex(),
                "origin": 2,
            },
        },
    ]

    return {
        "$schema": "./schema.json",
        "category": "status-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
