"""Generator for protocol/vectors/calls-encoding.json (E52-01).

Covers encode/decode vectors for the message types defined in
protocol/proto/tandem/v1/calls.proto (docs/protocol/SPEC.md #calls-channel):

    CallEvent { call_id (string, 1), direction (enum CallDirection, 2), state (enum CallState, 3),
                address (string, 4), normalized_e164 (string, 5), timestamp_ms (uint64, 6) }
    CallActionResult { request_id (string, 1), call_id (string, 2), success (bool, 3),
                       error_code (enum CallActionErrorCode, 4) }

Like sms-encoding.json, entries are the raw serialized message bytes for one message type at a
time; `input.kind` selects the message type (`callEvent`/`callActionResult`, both with
`input.messageHex`, or `callStateSequence` with `input.messageHexes`, an ordered list of CallEvent
bodies for one call).
"""

from __future__ import annotations

import hashlib
from typing import Any

CALL_DIRECTIONS = {
    "CALL_DIRECTION_UNSPECIFIED": 0,
    "CALL_DIRECTION_INCOMING": 1,
    "CALL_DIRECTION_OUTGOING": 2,
}

CALL_STATES = {
    "CALL_STATE_UNSPECIFIED": 0,
    "CALL_STATE_RINGING": 1,
    "CALL_STATE_DIALING": 2,
    "CALL_STATE_ACTIVE": 3,
    "CALL_STATE_ENDED": 4,
}

CALL_ACTION_ERROR_CODES = {
    "CALL_ACTION_ERROR_CODE_UNSPECIFIED": 0,
    "CALL_ACTION_ERROR_CODE_UNKNOWN_CALL": 1,
    "CALL_ACTION_ERROR_CODE_NOT_RINGING": 2,
    "CALL_ACTION_ERROR_CODE_NO_ACTIVE_CALL": 3,
    "CALL_ACTION_ERROR_CODE_PERMISSION_DENIED": 4,
    "CALL_ACTION_ERROR_CODE_INVALID_SUBSCRIPTION": 5,
    "CALL_ACTION_ERROR_CODE_NEEDS_PHONE_TAP": 6,
    "CALL_ACTION_ERROR_CODE_INVALID_NUMBER": 7,
    "CALL_ACTION_ERROR_CODE_RATE_LIMITED": 8,
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


def _field_string(field_number: int, value: str) -> bytes:
    """Encodes a string field (empty string omitted, matching proto3 default-value elision)."""
    if not value:
        return b""
    payload = value.encode("utf-8")
    return _tag(field_number, 2) + _varint(len(payload)) + payload


def encode_call_event(
    *,
    call_id: str,
    direction: int,
    state: int,
    address: str,
    normalized_e164: str,
    timestamp_ms: int,
) -> bytes:
    """Encodes a CallEvent message body."""
    return (
        _field_string(1, call_id)
        + _field_varint(2, direction)
        + _field_varint(3, state)
        + _field_string(4, address)
        + _field_string(5, normalized_e164)
        + _field_varint(6, timestamp_ms)
    )


def encode_call_action_result(
    *, request_id: str, call_id: str, success: bool, error_code: int
) -> bytes:
    """Encodes a CallActionResult message body."""
    return (
        _field_string(1, request_id)
        + _field_string(2, call_id)
        + _field_bool(3, success)
        + _field_varint(4, error_code)
    )


CALL_ID = "c1d4e8a2-7b3f-4a90-8e65-2f9d0b6a1c34"
REQUEST_ID = "9a7e5c31-4d28-4b6f-a0c3-5e1f8d2b7a46"
ADDRESS = "+41 79 555 01 00"
NORMALIZED_E164 = "+41795550100"
BASE_TIMESTAMP_MS = 1_700_000_000_000


def _call_event(state_name: str, offset_ms: int) -> bytes:
    return encode_call_event(
        call_id=CALL_ID,
        direction=CALL_DIRECTIONS["CALL_DIRECTION_INCOMING"],
        state=CALL_STATES[state_name],
        address=ADDRESS,
        normalized_e164=NORMALIZED_E164,
        timestamp_ms=BASE_TIMESTAMP_MS + offset_ms,
    )


def _call_action_result_vector(error_name: str, request_id: str, call_id: str) -> dict[str, Any]:
    message = encode_call_action_result(
        request_id=request_id,
        call_id=call_id,
        success=False,
        error_code=CALL_ACTION_ERROR_CODES[error_name],
    )
    slug = error_name.removeprefix("CALL_ACTION_ERROR_CODE_").lower().replace("_", "-")
    return {
        "id": f"call-action-result-{slug}",
        "description": (
            f"A failed CallActionResult with errorCode {error_name} decoding to the same enum "
            "value and echoing requestId on both codecs (docs/protocol/SPEC.md #calls-channel)."
        ),
        "input": {"kind": "callActionResult", "messageHex": message.hex()},
        "expected": {
            "requestId": request_id,
            "callId": call_id,
            "success": False,
            "errorCode": error_name,
        },
    }


def generate_calls_encoding_vectors() -> dict[str, Any]:
    """Generates CALLS-channel message encode/decode vectors."""

    ringing = _call_event("CALL_STATE_RINGING", 0)
    sequence = [
        ringing,
        _call_event("CALL_STATE_ACTIVE", 4_000),
        _call_event("CALL_STATE_ENDED", 64_000),
    ]

    vectors: list[dict[str, Any]] = [
        {
            "id": "call-event-ringing-incoming-round-trip",
            "description": (
                "An incoming RINGING CallEvent decoding to identical fields on both codecs and "
                "re-encoding to the same golden bytes (docs/protocol/SPEC.md #calls-channel)."
            ),
            "input": {"kind": "callEvent", "messageHex": ringing.hex()},
            "expected": {
                "callId": CALL_ID,
                "direction": "CALL_DIRECTION_INCOMING",
                "state": "CALL_STATE_RINGING",
                "address": ADDRESS,
                "normalizedE164": NORMALIZED_E164,
                "timestampMs": BASE_TIMESTAMP_MS,
                "messageSha256": hashlib.sha256(ringing).hexdigest(),
            },
        },
        {
            "id": "call-state-sequence-ringing-active-ended",
            "description": (
                "The CallEvent sequence of one incoming call (RINGING, ACTIVE, ENDED) decoding "
                "to the same callId, states and timestamps on both codecs (docs/protocol/SPEC.md "
                "#calls-channel \"Call events\")."
            ),
            "input": {
                "kind": "callStateSequence",
                "messageHexes": [event.hex() for event in sequence],
            },
            "expected": {
                "callId": CALL_ID,
                "states": ["CALL_STATE_RINGING", "CALL_STATE_ACTIVE", "CALL_STATE_ENDED"],
                "timestampsMs": [BASE_TIMESTAMP_MS, BASE_TIMESTAMP_MS + 4_000, BASE_TIMESTAMP_MS + 64_000],
            },
        },
        _call_action_result_vector(
            "CALL_ACTION_ERROR_CODE_UNKNOWN_CALL",
            REQUEST_ID,
            "00000000-0000-4000-8000-000000000000",
        ),
        _call_action_result_vector("CALL_ACTION_ERROR_CODE_INVALID_NUMBER", REQUEST_ID, ""),
        _call_action_result_vector("CALL_ACTION_ERROR_CODE_RATE_LIMITED", REQUEST_ID, ""),
    ]

    return {
        "$schema": "./schema.json",
        "category": "calls-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
