"""Reference generator + reference decoder for protocol/vectors/frame-encoding.json (E01-19).

Builds Envelope frames byte-by-byte (a minimal, self-contained protobuf wire-format encoder —
this module intentionally does not depend on the `protobuf` package) and decodes them back
against the frame-format and rejection rules in docs/protocol/SPEC.md #framing-and-envelope and
#errors-and-close-codes:

    frame = length_prefix envelope_bytes
    length_prefix = u32 big-endian, excludes itself, max 1 048 576 (1 MiB)

Every rejection case in SPEC.md's rejection-cases table (TOO_LARGE, BAD_LENGTH, TRUNCATED,
DECODE_FAILED, UNKNOWN_CHANNEL, UNKNOWN_PAYLOAD_TYPE) is implemented in `decode_frame` and
exercised by a vector below; see protocol/vectors/README.md for the manifest format and the
unknown-channel / unknown-payload-type encoding choices documented there.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass

MAX_ENVELOPE_BYTES = 1_048_576  # 1 MiB, 2^20 (SPEC.md #framing-and-envelope)

# Channel: protocol/proto/tandem/v1/envelope.proto. CHANNEL_UNSPECIFIED = 0 is reserved and never
# valid on the wire (UNKNOWN_CHANNEL).
CHANNEL_VALUES = {
    "CHANNEL_UNSPECIFIED": 0,
    "CHANNEL_CONTROL": 1,
    "CHANNEL_NOTIFY": 2,
    "CHANNEL_CLIPBOARD": 3,
    "CHANNEL_FILES": 4,
    "CHANNEL_SMS": 5,
    "CHANNEL_CONTACTS": 6,
    "CHANNEL_CALLS": 7,
    "CHANNEL_INPUT": 8,
    "CHANNEL_STATUS": 9,
    "CHANNEL_MEDIA_CONTROL": 10,
}
VALID_CHANNEL_VALUES = frozenset(v for k, v in CHANNEL_VALUES.items() if k != "CHANNEL_UNSPECIFIED")

# Envelope payload oneof field numbers (envelope.proto).
_FIELD_DEVICE_STATUS = 20
_FIELD_RING = 21


# --- minimal protobuf wire-format encoder -----------------------------------------------------


def _varint(value: int) -> bytes:
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
    return _varint((field_number << 3) | wire_type)


def _field_varint(field_number: int, value: int) -> bytes:
    return _tag(field_number, 0) + _varint(value)


def _field_len_delimited(field_number: int, payload: bytes) -> bytes:
    return _tag(field_number, 2) + _varint(len(payload)) + payload


def _encode_payload(kind: str) -> bytes:
    if kind == "ring":
        return _field_len_delimited(_FIELD_RING, b"")
    raise ValueError(f"unsupported recipe payload kind: {kind}")


def encode_device_status(*, battery_level: int, is_charging: bool, network_type: int, signal_level: int) -> bytes:
    return (
        _field_varint(1, battery_level)
        + _field_varint(2, 1 if is_charging else 0)
        + _field_varint(3, network_type)
        + _field_varint(4, signal_level)
    )


def build_envelope(*, channel: str, seq: int = 0, ack: int = 0, payload: tuple[str, bytes] | None) -> bytes:
    """Builds well-formed Envelope bytes. `seq`/`ack` of 0 are omitted (proto3 default-value
    wire omission); `payload` is `(kind, body_bytes)` with kind in {"deviceStatus", "ring"}, or
    None to leave the oneof unset."""
    parts = [_field_varint(1, CHANNEL_VALUES[channel])]
    if seq:
        parts.append(_field_varint(2, seq))
    if ack:
        parts.append(_field_varint(3, ack))
    if payload is not None:
        kind, body = payload
        field_number = {"deviceStatus": _FIELD_DEVICE_STATUS, "ring": _FIELD_RING}[kind]
        parts.append(_field_len_delimited(field_number, body))
    return b"".join(parts)


def build_frame(envelope_bytes: bytes, *, length_prefix: int | None = None) -> bytes:
    prefix = length_prefix if length_prefix is not None else len(envelope_bytes)
    return prefix.to_bytes(4, "big") + envelope_bytes


def solve_filler(*, fixed_overhead: int, target_total: int, field_number: int, fill_byte: int = 0x00) -> dict:
    """Computes a `filler` recipe (an unrecognized length-delimited field padding the envelope
    with a repeated fill byte) so that `fixed_overhead + filler-field-bytes == target_total`
    exactly. Used to describe a large envelope (e.g. the 1 MiB boundary vector) compactly,
    without committing the padded bytes themselves (see protocol/vectors/README.md)."""
    tag_len = len(_tag(field_number, 2))
    varint_len_guess = 1
    for _ in range(16):
        fill_length = target_total - fixed_overhead - tag_len - varint_len_guess
        if fill_length < 0:
            raise ValueError("target_total too small for the fixed overhead and filler tag")
        actual_len = len(_varint(fill_length))
        if actual_len == varint_len_guess:
            return {
                "fieldNumber": field_number,
                "wireType": "LENGTH_DELIMITED",
                "fillByte": f"{fill_byte:02x}",
                "fillLength": fill_length,
            }
        varint_len_guess = actual_len
    raise RuntimeError("failed to converge on a filler length")


def build_envelope_from_recipe(recipe: dict) -> bytes:
    """Inverse of `solve_filler` plus `build_envelope`: reconstructs the exact envelope bytes a
    compact `envelopeRecipe` describes (see protocol/vectors/README.md)."""
    parts = [_field_varint(1, CHANNEL_VALUES[recipe["channel"]])]
    if recipe.get("seq", 0):
        parts.append(_field_varint(2, recipe["seq"]))
    if recipe.get("ack", 0):
        parts.append(_field_varint(3, recipe["ack"]))
    payload = recipe.get("payload")
    if payload:
        parts.append(_encode_payload(payload["kind"]))
    filler = recipe.get("filler")
    if filler:
        fill_bytes = bytes.fromhex(filler["fillByte"]) * filler["fillLength"]
        parts.append(_field_len_delimited(filler["fieldNumber"], fill_bytes))
    return b"".join(parts)


def build_frame_from_vector(vector: dict) -> bytes:
    """Reconstructs the exact frame bytes a manifest entry's `input` describes, whether inlined
    as `frameHex` or described compactly as an `envelopeRecipe`."""
    entry_input = vector["input"]
    if "frameHex" in entry_input:
        return bytes.fromhex(entry_input["frameHex"])
    if "envelopeRecipe" in entry_input:
        envelope_bytes = build_envelope_from_recipe(entry_input["envelopeRecipe"])
        if len(envelope_bytes) != entry_input["envelopeLength"]:
            raise ValueError("envelopeRecipe did not reproduce the declared envelopeLength")
        return build_frame(envelope_bytes, length_prefix=entry_input["lengthPrefix"])
    raise ValueError("vector input has neither frameHex nor envelopeRecipe")


# --- minimal protobuf wire-format decoder (the "reference decoder") --------------------------


class DecodeError(Exception):
    """The envelope bytes are not a well-formed protobuf message (local reason DECODE_FAILED)."""


@dataclass(frozen=True)
class FrameDecodeResult:
    accepted: bool
    channel: int | None = None
    seq: int | None = None
    ack: int | None = None
    payload: str | None = None
    reason: str | None = None
    close_code: str | None = None


def _decode_envelope(data: bytes) -> tuple[int, int, int, str | None]:
    """Walks the raw protobuf wire format once, last-value-wins per field (including the
    `payload` oneof), skipping any field number this decoder does not recognize — exactly the
    forward-compatible behavior a real protobuf-lite parser exhibits for unknown fields."""
    channel = 0
    seq = 0
    ack = 0
    payload: str | None = None
    pos = 0
    length = len(data)
    while pos < length:
        tag, pos = _decode_varint(data, pos)
        field_number = tag >> 3
        wire_type = tag & 0x7
        if field_number == 0:
            raise DecodeError("field number 0 is illegal")
        if wire_type == 0:
            value, pos = _decode_varint(data, pos)
            if field_number == 1:
                channel = value
            elif field_number == 2:
                seq = value
            elif field_number == 3:
                ack = value
            # else: unrecognized varint field, ignored.
        elif wire_type == 1:
            if pos + 8 > length:
                raise DecodeError("truncated 64-bit field")
            pos += 8
        elif wire_type == 2:
            field_length, pos = _decode_varint(data, pos)
            if pos + field_length > length:
                raise DecodeError("truncated length-delimited field")
            if field_number == _FIELD_DEVICE_STATUS:
                payload = "deviceStatus"
            elif field_number == _FIELD_RING:
                payload = "ring"
            # else: unrecognized bytes field, ignored (this is how an unassigned oneof field
            # number, e.g. envelope.proto's reserved 22-29 range, is distinguished from a
            # recognized payload: it is simply skipped, leaving `payload` unset).
            pos += field_length
        elif wire_type == 5:
            if pos + 4 > length:
                raise DecodeError("truncated 32-bit field")
            pos += 4
        else:
            raise DecodeError(f"unsupported wire type {wire_type}")
    return channel, seq, ack, payload


def _decode_varint(data: bytes, pos: int) -> tuple[int, int]:
    result = 0
    shift = 0
    length = len(data)
    while True:
        if pos >= length:
            raise DecodeError("truncated varint")
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if not (byte & 0x80):
            return result, pos
        shift += 7
        if shift > 63:
            raise DecodeError("varint too long")


def decode_frame(data: bytes) -> FrameDecodeResult:
    """Reference decoder for one frame, implementing SPEC.md #framing-and-envelope's rejection
    table exactly, in order: TOO_LARGE and BAD_LENGTH are checked against the 4-byte prefix alone
    (before any payload byte is read, per SPEC.md), then TRUNCATED, then DECODE_FAILED,
    UNKNOWN_CHANNEL, and UNKNOWN_PAYLOAD_TYPE."""
    if len(data) < 4:
        return FrameDecodeResult(False, reason="TRUNCATED", close_code="MALFORMED_FRAME")

    length_prefix = int.from_bytes(data[:4], "big")
    if length_prefix > MAX_ENVELOPE_BYTES:
        return FrameDecodeResult(False, reason="TOO_LARGE", close_code="MALFORMED_FRAME")
    if length_prefix == 0:
        return FrameDecodeResult(False, reason="BAD_LENGTH", close_code="MALFORMED_FRAME")

    supplied = data[4:]
    if len(supplied) < length_prefix:
        return FrameDecodeResult(False, reason="TRUNCATED", close_code="MALFORMED_FRAME")
    envelope_bytes = supplied[:length_prefix]

    try:
        channel, seq, ack, payload = _decode_envelope(envelope_bytes)
    except DecodeError:
        return FrameDecodeResult(False, reason="DECODE_FAILED", close_code="MALFORMED_FRAME")

    if channel not in VALID_CHANNEL_VALUES:
        return FrameDecodeResult(False, reason="UNKNOWN_CHANNEL", close_code="MALFORMED_FRAME")
    if payload is None:
        return FrameDecodeResult(False, reason="UNKNOWN_PAYLOAD_TYPE", close_code="MALFORMED_FRAME")

    return FrameDecodeResult(True, channel=channel, seq=seq, ack=ack, payload=payload)


# --- manifest generation (E01-19) --------------------------------------------------------------


def _valid_vector(*, vector_id: str, description: str, envelope_bytes: bytes, channel: str, seq: int, ack: int, payload: str) -> dict:
    frame = build_frame(envelope_bytes)
    return {
        "id": vector_id,
        "description": description,
        "input": {
            "frameHex": frame.hex(),
            "lengthPrefix": len(envelope_bytes),
            "suppliedEnvelopeLength": len(envelope_bytes),
        },
        "expected": {
            "channel": channel,
            "seq": seq,
            "ack": ack,
            "payload": payload,
            "envelopeLength": len(envelope_bytes),
        },
    }


def _invalid_vector(*, vector_id: str, description: str, envelope_bytes: bytes, length_prefix: int, local_reason: str) -> dict:
    return {
        "id": vector_id,
        "description": description,
        "input": {
            "frameHex": build_frame(envelope_bytes, length_prefix=length_prefix).hex(),
            "lengthPrefix": length_prefix,
            "suppliedEnvelopeLength": len(envelope_bytes),
        },
        "expectedError": "malformedFrame",
        "closeCode": "MALFORMED_FRAME",
        "localReason": local_reason,
    }


def _invalid_prefix_only_vector(*, vector_id: str, description: str, length_prefix: int, local_reason: str) -> dict:
    return _invalid_vector(
        vector_id=vector_id,
        description=description,
        envelope_bytes=b"",
        length_prefix=length_prefix,
        local_reason=local_reason,
    )


def generate_frame_encoding_vectors() -> dict:
    min_envelope = build_envelope(channel="CHANNEL_STATUS", seq=1, ack=0, payload=("ring", b""))
    typical_envelope = build_envelope(
        channel="CHANNEL_STATUS",
        seq=42,
        ack=41,
        payload=(
            "deviceStatus",
            encode_device_status(battery_level=76, is_charging=True, network_type=2, signal_level=3),
        ),
    )

    max_recipe = {
        "channel": "CHANNEL_STATUS",
        "seq": 1,
        "ack": 0,
        "payload": {"kind": "ring"},
        "filler": solve_filler(
            fixed_overhead=len(min_envelope),
            target_total=MAX_ENVELOPE_BYTES,
            field_number=500_000,
        ),
    }
    max_envelope = build_envelope_from_recipe(max_recipe)
    if len(max_envelope) != MAX_ENVELOPE_BYTES:
        raise AssertionError("max-size recipe did not resolve to exactly MAX_ENVELOPE_BYTES")
    max_frame = build_frame(max_envelope)

    # Same shape as frame-min-size (seq=1, empty Ring payload), but channel is 99 — outside the
    # nine enumerated channel values — instead of a real Channel value.
    unknown_channel_envelope = _field_varint(1, 99) + _field_varint(2, 1) + _field_len_delimited(21, b"")

    unknown_payload_envelope = _field_varint(1, CHANNEL_VALUES["CHANNEL_STATUS"]) + _field_varint(2, 1) + _field_varint(25, 7)

    decode_failed_envelope = bytes([0x08, 0x96])  # tag for field 1 varint, then an unterminated varint byte

    vectors = [
        _valid_vector(
            vector_id="frame-min-size",
            description=(
                "Smallest legal Envelope: channel and seq set, ack omitted at its proto3 "
                "default (0), payload an empty Ring message."
            ),
            envelope_bytes=min_envelope,
            channel="CHANNEL_STATUS",
            seq=1,
            ack=0,
            payload="ring",
        ),
        _valid_vector(
            vector_id="frame-typical-size",
            description="Typical Envelope: a populated DeviceStatus payload on the STATUS channel.",
            envelope_bytes=typical_envelope,
            channel="CHANNEL_STATUS",
            seq=42,
            ack=41,
            payload="deviceStatus",
        ),
        {
            "id": "frame-max-size-exact",
            "description": (
                "Envelope at exactly the 1 MiB (1 048 576 byte) maximum: the same minimal Ring "
                "payload as frame-min-size, padded to the boundary with one unrecognized "
                "high-numbered field carrying repeated fill bytes (see the compact-recipe note "
                "in protocol/vectors/README.md) so this manifest does not embed a 1 MiB blob."
            ),
            "input": {
                "envelopeRecipe": max_recipe,
                "envelopeLength": MAX_ENVELOPE_BYTES,
                "lengthPrefix": MAX_ENVELOPE_BYTES,
            },
            "expected": {
                "channel": "CHANNEL_STATUS",
                "seq": 1,
                "ack": 0,
                "payload": "ring",
                "envelopeLength": MAX_ENVELOPE_BYTES,
                "frameSha256": hashlib.sha256(max_frame).hexdigest(),
            },
        },
        _invalid_prefix_only_vector(
            vector_id="frame-oversize-plus-one",
            description=(
                "length_prefix = 1 MiB + 1 (1 048 577): rejected using only the 4 prefix bytes, "
                "before any payload byte is read or buffered (SPEC.md #framing-and-envelope)."
            ),
            length_prefix=MAX_ENVELOPE_BYTES + 1,
            local_reason="TOO_LARGE",
        ),
        _invalid_prefix_only_vector(
            vector_id="frame-bad-length-0xffffffff",
            description=(
                "length_prefix = 0xFFFFFFFF, the maximum representable u32: also oversize, but "
                "exercises the unsigned-overflow boundary distinct from the 1 MiB + 1 vector."
            ),
            length_prefix=0xFFFFFFFF,
            local_reason="TOO_LARGE",
        ),
        _invalid_prefix_only_vector(
            vector_id="frame-bad-length-zero",
            description="length_prefix = 0: never valid, rejected as BAD_LENGTH regardless of any following bytes.",
            length_prefix=0,
            local_reason="BAD_LENGTH",
        ),
        {
            "id": "frame-truncated",
            "description": (
                "length_prefix matches a well-formed Envelope (frame-typical-size's), but the "
                "connection delivers one byte fewer than that before closing."
            ),
            "input": {
                "frameHex": build_frame(typical_envelope[:-1], length_prefix=len(typical_envelope)).hex(),
                "lengthPrefix": len(typical_envelope),
                "suppliedEnvelopeLength": len(typical_envelope) - 1,
            },
            "expectedError": "malformedFrame",
            "closeCode": "MALFORMED_FRAME",
            "localReason": "TRUNCATED",
        },
        _invalid_vector(
            vector_id="frame-decode-failed",
            description=(
                "The length_prefix bytes are fully delivered but fail to decode as a well-formed "
                "Envelope: an unterminated varint (continuation bit set on the last available byte)."
            ),
            envelope_bytes=decode_failed_envelope,
            length_prefix=len(decode_failed_envelope),
            local_reason="DECODE_FAILED",
        ),
        _invalid_vector(
            vector_id="frame-unknown-channel",
            description=(
                "channel = 99, a value outside the nine enumerated channels "
                "(SPEC.md #channels-and-flow-control-credits); otherwise a well-formed Envelope."
            ),
            envelope_bytes=unknown_channel_envelope,
            length_prefix=len(unknown_channel_envelope),
            local_reason="UNKNOWN_CHANNEL",
        ),
        _invalid_vector(
            vector_id="frame-unknown-payload-type",
            description=(
                "The payload oneof is unset: field 25 (in envelope.proto's reserved 22-29 "
                "status.proto range, not yet assigned to device_status or ring) is present "
                "instead of a recognized payload field."
            ),
            envelope_bytes=unknown_payload_envelope,
            length_prefix=len(unknown_payload_envelope),
            local_reason="UNKNOWN_PAYLOAD_TYPE",
        ),
    ]

    return {
        "$schema": "./schema.json",
        "category": "frame-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
