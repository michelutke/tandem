"""Generator for protocol/vectors/media-control-encoding.json (E72-02).

Covers encode/decode vectors for the message types of docs/protocol/SPEC.md #media-control:

    NowPlaying { title (string, 1), artist (string, 2), state (PlaybackState, 3),
                 album (optional string, 4), duration_ms (optional int64, 5) }
    PlayPause, Next, Previous, Stop (empty messages)
    CapabilityUnavailable { feature (Feature, 1) }

(media_control.proto; Envelope.payload fields 130-135). Entries are the raw serialized message bytes
for one message type at a time; `input.kind` selects the message type (`nowPlaying`, `playPause`,
`next`, `previous`, `stop`, `capabilityUnavailable`, all with `input.messageHex`). `expected.summary`
is the canonical decoded view both codecs must reproduce.
"""

from __future__ import annotations

import hashlib
from typing import Any

PLAYBACK_STATE_PLAYING = 1
PLAYBACK_STATE_PAUSED = 2
PLAYBACK_STATE_STOPPED = 3
FEATURE_MEDIA_CONTROL = 1

TITLE_MAX_CHARS = 256
ARTIST_MAX_CHARS = 128
ABSENT = "<absent>"


def _varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def _field_varint(field_number: int, value: int) -> bytes:
    """Encodes a varint field (omitted when zero, matching proto3 default-value elision)."""
    if value == 0:
        return b""
    return _varint(field_number << 3) + _varint(value)


def _field_string(field_number: int, value: str) -> bytes:
    """Encodes a non-optional string field (omitted when empty)."""
    if not value:
        return b""
    return _field_optional_string(field_number, value)


def _field_optional_string(field_number: int, value: str) -> bytes:
    """Encodes an explicit-presence string field (emitted even when empty)."""
    raw = value.encode("utf-8")
    return _varint((field_number << 3) | 2) + _varint(len(raw)) + raw


def encode_now_playing(
    *,
    title: str,
    artist: str,
    state: int,
    album: str | None = None,
    duration_ms: int | None = None,
) -> bytes:
    """Encodes a NowPlaying message body."""
    body = _field_string(1, title) + _field_string(2, artist) + _field_varint(3, state)
    if album is not None:
        body += _field_optional_string(4, album)
    if duration_ms is not None:
        body += _varint(5 << 3) + _varint(duration_ms)
    return body


def encode_capability_unavailable(*, feature: int) -> bytes:
    """Encodes a CapabilityUnavailable message body."""
    return _field_varint(1, feature)


def _now_playing_summary(
    title: str, artist: str, state: int, album: str | None, duration_ms: int | None
) -> str:
    album_text = ABSENT if album is None else album
    duration_text = ABSENT if duration_ms is None else str(duration_ms)
    return (
        f"title={title}|artist={artist}|state={state}|album={album_text}|durationMs={duration_text}"
    )


def _vector(slug: str, description: str, kind: str, message: bytes, summary: str) -> dict[str, Any]:
    return {
        "id": slug,
        "description": description,
        "input": {"kind": kind, "messageHex": message.hex()},
        "expected": {"summary": summary, "messageSha256": hashlib.sha256(message).hexdigest()},
    }


def _now_playing_vector(
    slug: str,
    description: str,
    *,
    title: str,
    artist: str,
    state: int,
    album: str | None = None,
    duration_ms: int | None = None,
) -> dict[str, Any]:
    return _vector(
        slug,
        description,
        "nowPlaying",
        encode_now_playing(
            title=title, artist=artist, state=state, album=album, duration_ms=duration_ms
        ),
        _now_playing_summary(title, artist, state, album, duration_ms),
    )


def _command_vector(slug: str, kind: str, name: str) -> dict[str, Any]:
    return _vector(
        slug,
        (
            f"{name}, an empty message under proto3 default elision, decoding on both codecs and "
            "re-encoding to the same golden (zero-length) bytes (docs/protocol/SPEC.md "
            "#media-control)."
        ),
        kind,
        b"",
        "empty",
    )


def generate_media_control_encoding_vectors() -> dict[str, Any]:
    """Generates media-control message encode/decode vectors."""

    vectors: list[dict[str, Any]] = [
        _now_playing_vector(
            "now-playing-playing-title-artist-round-trip",
            (
                "NowPlaying with title, artist and PLAYING state and no album or duration, "
                "round-tripping to the same golden bytes on both codecs (docs/protocol/SPEC.md "
                "#media-control)."
            ),
            title="Blue in Green",
            artist="Miles Davis",
            state=PLAYBACK_STATE_PLAYING,
        ),
        _now_playing_vector(
            "now-playing-all-fields-round-trip",
            (
                "NowPlaying with every field set (PAUSED, album, duration_ms) round-tripping to "
                "the same golden bytes on both codecs."
            ),
            title="So What",
            artist="Miles Davis",
            state=PLAYBACK_STATE_PAUSED,
            album="Kind of Blue",
            duration_ms=562000,
        ),
        _now_playing_vector(
            "now-playing-unicode-round-trip",
            "NowPlaying with non-ASCII UTF-8 title and artist and STOPPED state round-tripping.",
            title="Für Elise – 夜",
            artist="Beethoven ♪",
            state=PLAYBACK_STATE_STOPPED,
        ),
        _now_playing_vector(
            "now-playing-empty-album-present-round-trip",
            (
                "NowPlaying with album explicitly present but empty: explicit presence survives "
                "the round trip on both codecs, distinct from an absent album."
            ),
            title="Untitled",
            artist="Unknown",
            state=PLAYBACK_STATE_PLAYING,
            album="",
        ),
        _now_playing_vector(
            "now-playing-max-length-strings-round-trip",
            (
                f"NowPlaying with a {TITLE_MAX_CHARS}-character title and a {ARTIST_MAX_CHARS}-"
                "character artist (the SPEC caps) round-tripping to the same golden bytes."
            ),
            title="t" * TITLE_MAX_CHARS,
            artist="a" * ARTIST_MAX_CHARS,
            state=PLAYBACK_STATE_PLAYING,
        ),
        _command_vector("play-pause-round-trip", "playPause", "PlayPause"),
        _command_vector("next-round-trip", "next", "Next"),
        _command_vector("previous-round-trip", "previous", "Previous"),
        _command_vector("stop-round-trip", "stop", "Stop"),
        _vector(
            "capability-unavailable-media-control-round-trip",
            (
                "CapabilityUnavailable { feature: FEATURE_MEDIA_CONTROL } decoding to feature = 1 "
                "on both codecs and re-encoding to the same golden bytes."
            ),
            "capabilityUnavailable",
            encode_capability_unavailable(feature=FEATURE_MEDIA_CONTROL),
            f"feature={FEATURE_MEDIA_CONTROL}",
        ),
    ]

    return {
        "$schema": "./schema.json",
        "category": "media-control-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
