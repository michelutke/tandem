"""Generator for protocol/vectors/input-encoding.json (E62-01).

Covers InputEvent of docs/protocol/SPEC.md #input-events (input.proto; Envelope.payload field 100):

    InputEvent { session_id (bytes, 1), oneof event { tap (2), swipe (3), scroll (4),
                                                      global_action (5), set_text (6), text_edit (7) } }
    Tap { x (1), y (2) }  Swipe { x1 (1), y1 (2), x2 (3), y2 (4), duration_ms (5) }
    Scroll { x (1), y (2), dx (sint32, 3), dy (sint32, 4) }  GlobalAction { action (enum, 1) }
    SetText { text (string, 1) }  TextEdit { oneof edit { insert (1), delete_backward (2), ime_enter (3) } }

One entry shape, `input.kind` = `inputEvent`: `input.messageHex` is a serialized InputEvent,
`input.activeSessionIdHex` the active mirror session's id and `input.windowWidth`/`windowHeight` the
reported window size. Positive entries carry `expected.summary` (canonical decoded view) and
`expected.messageSha256`; both codecs also re-encode to the same bytes. Negative entries carry
`expectedError`, the name of the first rule the event violates (session reference first, then the
variant's own ranges); the event is dropped, never clamped.
"""

from __future__ import annotations

import hashlib
from typing import Any

from media_encoding import _field_bytes, _field_varint, _tag, _varint
from media_frame_encoding import _submessage

SESSION_ID_LENGTH = 16
WINDOW_WIDTH = 1080
WINDOW_HEIGHT = 2400
MAX_TEXT_CHARACTERS = 4096
ACTION_HOME = 2
ACTION_UNKNOWN = 99

ACTIVE_SESSION = bytes(range(0x10, 0x20))
STALE_SESSION = bytes(range(0x20, 0x30))
FOREIGN_SESSION = bytes(range(0x80, 0x90))

_EVENT_FIELD = {"tap": 2, "swipe": 3, "scroll": 4, "globalAction": 5, "setText": 6, "textEdit": 7}


def _zigzag(value: int) -> int:
    return (value << 1) ^ (value >> 31)


def _field_sint32(field_number: int, value: int) -> bytes:
    return _field_varint(field_number, _zigzag(value))


def encode_tap(*, x: int, y: int) -> bytes:
    return _field_varint(1, x) + _field_varint(2, y)


def encode_swipe(*, x1: int, y1: int, x2: int, y2: int, duration_ms: int) -> bytes:
    return (
        _field_varint(1, x1)
        + _field_varint(2, y1)
        + _field_varint(3, x2)
        + _field_varint(4, y2)
        + _field_varint(5, duration_ms)
    )


def encode_scroll(*, x: int, y: int, dx: int, dy: int) -> bytes:
    return _field_varint(1, x) + _field_varint(2, y) + _field_sint32(3, dx) + _field_sint32(4, dy)


def encode_global_action(*, action: int) -> bytes:
    return _field_varint(1, action)


def encode_set_text(*, text: str) -> bytes:
    return _field_bytes(1, text.encode("utf-8"))


def encode_text_edit_insert(text: str) -> bytes:
    return _tag(1, 2) + _varint(len(text.encode("utf-8"))) + text.encode("utf-8")


def encode_text_edit_delete(count: int) -> bytes:
    return _tag(2, 0) + _varint(count)


def encode_text_edit_ime_enter() -> bytes:
    return _tag(3, 2) + _varint(0)


def encode_input_event(session_id: bytes, kind: str, body: bytes) -> bytes:
    return _field_bytes(1, session_id) + _submessage(_EVENT_FIELD[kind], body)


def _positive(vector_id: str, description: str, kind: str, body: bytes, summary: str) -> dict[str, Any]:
    message = encode_input_event(ACTIVE_SESSION, kind, body)
    return {
        "id": vector_id,
        "description": description,
        "input": _input(message, ACTIVE_SESSION),
        "expected": {"summary": summary, "messageSha256": hashlib.sha256(message).hexdigest()},
    }


def _negative(
    vector_id: str, description: str, error: str, kind: str, body: bytes, session_id: bytes = ACTIVE_SESSION
) -> dict[str, Any]:
    message = encode_input_event(session_id, kind, body)
    return {
        "id": vector_id,
        "description": description,
        "input": _input(message, ACTIVE_SESSION),
        "expectedError": error,
    }


def _input(message: bytes, active_session: bytes) -> dict[str, Any]:
    return {
        "kind": "inputEvent",
        "messageHex": message.hex(),
        "activeSessionIdHex": active_session.hex(),
        "windowWidth": WINDOW_WIDTH,
        "windowHeight": WINDOW_HEIGHT,
    }


def _positive_vectors() -> list[dict[str, Any]]:
    return [
        _positive(
            "input-event-tap-round-trip",
            "Tap inside the window, bound to the active session, round-tripping to golden bytes.",
            "tap",
            encode_tap(x=540, y=1200),
            "variant=tap|x=540|y=1200",
        ),
        _positive(
            "input-event-tap-origin-round-trip",
            "Tap at (0, 0), an empty Tap body that is still present in the oneof, round-tripping.",
            "tap",
            encode_tap(x=0, y=0),
            "variant=tap|x=0|y=0",
        ),
        _positive(
            "input-event-swipe-round-trip",
            "Swipe over 300 ms inside the window round-tripping to golden bytes.",
            "swipe",
            encode_swipe(x1=540, y1=1800, x2=540, y2=600, duration_ms=300),
            "variant=swipe|x1=540|y1=1800|x2=540|y2=600|durationMs=300",
        ),
        _positive(
            "input-event-scroll-round-trip",
            "Scroll with a negative dy (sint32 zigzag) round-tripping to golden bytes.",
            "scroll",
            encode_scroll(x=540, y=1200, dx=0, dy=-120),
            "variant=scroll|x=540|y=1200|dx=0|dy=-120",
        ),
        _positive(
            "input-event-global-action-round-trip",
            "GlobalAction HOME round-tripping to golden bytes.",
            "globalAction",
            encode_global_action(action=ACTION_HOME),
            f"variant=globalAction|action={ACTION_HOME}",
        ),
        _positive(
            "input-event-set-text-round-trip",
            "SetText with non-ASCII text round-tripping to golden bytes.",
            "setText",
            encode_set_text(text="Grüezi 👋"),
            "variant=setText|text=Grüezi 👋",
        ),
        _positive(
            "input-event-set-text-cap-length",
            "SetText of exactly 4096 characters is accepted.",
            "setText",
            encode_set_text(text="a" * MAX_TEXT_CHARACTERS),
            f"variant=setText|text={'a' * MAX_TEXT_CHARACTERS}",
        ),
        _positive(
            "input-event-text-edit-insert-round-trip",
            "TextEdit.insert round-tripping to golden bytes.",
            "textEdit",
            encode_text_edit_insert("hello"),
            "variant=textEdit|insert=hello",
        ),
        _positive(
            "input-event-text-edit-delete-backward-round-trip",
            "TextEdit.deleteBackward 64 (the maximum) round-tripping to golden bytes.",
            "textEdit",
            encode_text_edit_delete(64),
            "variant=textEdit|deleteBackward=64",
        ),
        _positive(
            "input-event-text-edit-ime-enter-round-trip",
            "TextEdit.imeEnter round-tripping to golden bytes.",
            "textEdit",
            encode_text_edit_ime_enter(),
            "variant=textEdit|imeEnter",
        ),
    ]


def _session_negatives() -> list[dict[str, Any]]:
    tap = encode_tap(x=10, y=10)
    return [
        _negative(
            "input-event-missing-session-reference",
            "An InputEvent without session_id is rejected by both parsers (invariant 8).",
            "missingSessionReference",
            "tap",
            tap,
            session_id=b"",
        ),
        _negative(
            "input-event-short-session-reference",
            "An InputEvent whose session_id is not exactly 16 bytes is rejected as a missing reference.",
            "missingSessionReference",
            "tap",
            tap,
            session_id=ACTIVE_SESSION[:8],
        ),
        _negative(
            "input-event-stale-session",
            "An InputEvent bound to a previous (stale) mirror session id is dropped.",
            "sessionMismatch",
            "tap",
            tap,
            session_id=STALE_SESSION,
        ),
        _negative(
            "input-event-foreign-session",
            "An InputEvent bound to a session id this device never issued is dropped.",
            "sessionMismatch",
            "tap",
            tap,
            session_id=FOREIGN_SESSION,
        ),
    ]


def _range_negatives() -> list[dict[str, Any]]:
    return [
        _negative(
            "input-event-tap-x-out-of-range",
            "Tap with x equal to the window width is dropped, never clamped.",
            "coordinatesOutOfRange",
            "tap",
            encode_tap(x=WINDOW_WIDTH, y=10),
        ),
        _negative(
            "input-event-swipe-end-out-of-range",
            "Swipe whose end point lies below the window is dropped.",
            "coordinatesOutOfRange",
            "swipe",
            encode_swipe(x1=10, y1=10, x2=10, y2=WINDOW_HEIGHT + 500, duration_ms=300),
        ),
        _negative(
            "input-event-scroll-origin-out-of-range",
            "Scroll anchored outside the window is dropped.",
            "coordinatesOutOfRange",
            "scroll",
            encode_scroll(x=5000, y=10, dx=0, dy=40),
        ),
        _negative(
            "input-event-swipe-duration-zero",
            "Swipe with durationMs 0 is rejected.",
            "durationOutOfRange",
            "swipe",
            encode_swipe(x1=10, y1=10, x2=20, y2=20, duration_ms=0),
        ),
        _negative(
            "input-event-swipe-duration-over-max",
            "Swipe with durationMs 5001 is rejected.",
            "durationOutOfRange",
            "swipe",
            encode_swipe(x1=10, y1=10, x2=20, y2=20, duration_ms=5001),
        ),
        _negative(
            "input-event-global-action-unknown",
            "GlobalAction with a value this version does not define is dropped.",
            "unknownGlobalAction",
            "globalAction",
            encode_global_action(action=ACTION_UNKNOWN),
        ),
        _negative(
            "input-event-global-action-unspecified",
            "GlobalAction UNSPECIFIED (an empty body) is dropped.",
            "unknownGlobalAction",
            "globalAction",
            b"",
        ),
        _negative(
            "input-event-set-text-over-cap",
            "SetText of 4097 characters is rejected.",
            "textTooLong",
            "setText",
            encode_set_text(text="a" * (MAX_TEXT_CHARACTERS + 1)),
        ),
        _negative(
            "input-event-text-edit-insert-over-cap",
            "TextEdit.insert of 4097 characters is rejected.",
            "textTooLong",
            "textEdit",
            encode_text_edit_insert("a" * (MAX_TEXT_CHARACTERS + 1)),
        ),
        _negative(
            "input-event-text-edit-delete-zero",
            "TextEdit.deleteBackward 0 is rejected.",
            "deleteCountOutOfRange",
            "textEdit",
            encode_text_edit_delete(0),
        ),
        _negative(
            "input-event-text-edit-delete-over-max",
            "TextEdit.deleteBackward 65 is rejected.",
            "deleteCountOutOfRange",
            "textEdit",
            encode_text_edit_delete(65),
        ),
    ]


def generate_input_encoding_vectors() -> dict[str, Any]:
    """Generates InputEvent encode/decode and validation vectors."""

    return {
        "$schema": "./schema.json",
        "category": "input-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": _positive_vectors() + _session_negatives() + _range_negatives(),
    }
