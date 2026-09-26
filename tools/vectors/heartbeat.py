"""Generator for protocol/vectors/heartbeat.json (E20-01).

Covers `docs/protocol/SPEC.md` #heartbeat: the Heartbeat message (E01-12, E01-07 liveness
contract). Heartbeat is an empty message message, defined in control.proto.

Every Heartbeat is an ordinary CONTROL-channel Envelope (E01-03, E01-10), subject to the
usual seq/ack rules. The message carries no fields; encoding is deterministic.

This module generates:
1. A round-trip encode/decode vector where both codecs produce byte-identical encodings.
2. A truncated-frame vector where both codecs reject with a decode error.
"""

from __future__ import annotations

from typing import Any

# CONTROL channel is 8 (from channel.proto)
CONTROL_CHANNEL = 8

# Heartbeat message type is field 18 in the Envelope payload oneof (control.proto)
HEARTBEAT_FIELD_NUMBER = 18
HEARTBEAT_WIRE_TYPE = 2  # LENGTH_DELIMITED


def _encode_varint(value: int) -> bytes:
    """Encode an unsigned integer as a varint (little-endian base-128)."""
    result = []
    while value >= 0x80:
        result.append((value & 0x7F) | 0x80)
        value >>= 7
    result.append(value & 0x7F)
    return bytes(result)


def _encode_field_tag(field_number: int, wire_type: int) -> bytes:
    """Encode a protobuf field tag: (field_number << 3) | wire_type."""
    return _encode_varint((field_number << 3) | wire_type)


def _encode_length_delimited(data: bytes) -> bytes:
    """Encode a length-delimited field: length as varint followed by data."""
    return _encode_varint(len(data)) + data


def _encode_heartbeat() -> bytes:
    """Encode an empty Heartbeat message: just the field tag with zero-length data.

    Heartbeat {} in protobuf3 encodes as:
    - field number 18 (heartbeat), wire type 2 (LENGTH_DELIMITED)
    - tag = (18 << 3) | 2 = 144 | 2 = 146 = 0x92
    - length = 0 (empty message)
    - payload = (empty)
    Result: 0x92 0x00
    """
    tag = _encode_field_tag(HEARTBEAT_FIELD_NUMBER, HEARTBEAT_WIRE_TYPE)
    return tag + b"\x00"


def _encode_envelope(channel: int, seq: int, ack: int, payload: bytes) -> bytes:
    """Encode an Envelope: channel (field 1), seq (field 2), ack (field 3), payload.

    Each field is encoded as:
    - field 1 (channel): varint tag (0x08) + channel varint
    - field 2 (seq): varint tag (0x10) + seq varint
    - field 3 (ack): varint tag (0x18) + ack varint (omitted if 0 in proto3)
    - field 18 (heartbeat): tag 0x92 + length + data
    """
    envelope = b""

    # channel (field 1, wire type 0 = VARINT)
    envelope += b"\x08"  # field tag: (1 << 3) | 0
    envelope += _encode_varint(channel)

    # seq (field 2, wire type 0 = VARINT)
    envelope += b"\x10"  # field tag: (2 << 3) | 0
    envelope += _encode_varint(seq)

    # ack (field 3, wire type 0 = VARINT) - omit if 0 (proto3 default)
    if ack > 0:
        envelope += b"\x18"  # field tag: (3 << 3) | 0
        envelope += _encode_varint(ack)

    # payload (heartbeat message)
    envelope += payload

    return envelope


def _build_frame(channel: int, seq: int, ack: int) -> bytes:
    """Build a complete frame with 4-byte big-endian length prefix followed by envelope."""
    payload = _encode_heartbeat()
    envelope = _encode_envelope(channel, seq, ack, payload)
    length_prefix = len(envelope).to_bytes(4, "big")
    return length_prefix + envelope


def generate_heartbeat_vectors() -> dict[str, Any]:
    """Generate heartbeat test vectors for E20-01."""

    # A valid heartbeat on CONTROL channel with seq=1, ack=0
    heartbeat_minimal = _build_frame(CONTROL_CHANNEL, 1, 0)

    # A valid heartbeat on CONTROL channel with seq=42, ack=41
    heartbeat_typical = _build_frame(CONTROL_CHANNEL, 42, 41)

    # A truncated frame: the length prefix says one byte, but supply zero bytes
    truncated_zero = b"\x00\x00\x00\x01"  # length prefix = 1
    # (no envelope bytes follow)

    # A truncated frame: the length prefix says 7 bytes, but only supply 6
    heartbeat_7 = _build_frame(CONTROL_CHANNEL, 1, 0)
    envelope_7 = heartbeat_7[4:]  # extract just the envelope part
    if len(envelope_7) >= 7:
        truncated_short = b"\x00\x00\x00\x07" + envelope_7[:6]  # truncate by 1 byte
    else:
        # Build a specific 7-byte envelope
        truncated_short = b"\x00\x00\x00\x07\x08\x08\x10\x01\x92\x00" # Length mismatch

    return {
        "$schema": "./schema.json",
        "category": "heartbeat",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": [
            {
                "id": "heartbeat-roundtrip-minimal",
                "description": "Heartbeat on CONTROL channel with seq=1, ack=0 (omitted at proto3 default). Both codecs must produce the same encoding.",
                "input": {
                    "frameHex": heartbeat_minimal.hex(),
                    "lengthPrefix": len(heartbeat_minimal) - 4,
                    "suppliedEnvelopeLength": len(heartbeat_minimal) - 4,
                },
                "expected": {
                    "channel": "CHANNEL_CONTROL",
                    "seq": 1,
                    "ack": 0,
                    "payload": "heartbeat",
                    "envelopeLength": len(heartbeat_minimal) - 4,
                },
            },
            {
                "id": "heartbeat-roundtrip-with-ack",
                "description": "Heartbeat on CONTROL channel with seq=42, ack=41. Both codecs must produce the same encoding.",
                "input": {
                    "frameHex": heartbeat_typical.hex(),
                    "lengthPrefix": len(heartbeat_typical) - 4,
                    "suppliedEnvelopeLength": len(heartbeat_typical) - 4,
                },
                "expected": {
                    "channel": "CHANNEL_CONTROL",
                    "seq": 42,
                    "ack": 41,
                    "payload": "heartbeat",
                    "envelopeLength": len(heartbeat_typical) - 4,
                },
            },
            {
                "id": "heartbeat-truncated-zero-bytes",
                "description": "Frame with length_prefix = 1 but zero envelope bytes supplied. Both codecs must reject with a decode error (TRUNCATED).",
                "input": {
                    "frameHex": truncated_zero.hex(),
                    "lengthPrefix": 1,
                    "suppliedEnvelopeLength": 0,
                },
                "expectedError": "malformedFrame",
                "closeCode": "MALFORMED_FRAME",
                "localReason": "TRUNCATED",
            },
            {
                "id": "heartbeat-truncated-one-byte-short",
                "description": "Frame with length_prefix = 7 but only 6 envelope bytes supplied (truncated by 1 byte). Both codecs must reject with a decode error (TRUNCATED).",
                "input": {
                    "frameHex": truncated_short.hex(),
                    "lengthPrefix": 7,
                    "suppliedEnvelopeLength": 6,
                },
                "expectedError": "malformedFrame",
                "closeCode": "MALFORMED_FRAME",
                "localReason": "TRUNCATED",
            },
        ],
    }
