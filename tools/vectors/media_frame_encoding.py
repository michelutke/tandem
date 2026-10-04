"""Generator for protocol/vectors/media-frame-encoding.json (E61-01).

Covers the media-connection messages of docs/protocol/SPEC.md #media-frame-semantics:

    MediaMessage { oneof payload { media_format (1), media_frame (2), keyframe_request (3),
                                   rotation_changed (4) } } (media.proto; frame body after MediaHello)
    MediaFormat { codec (enum, 1), width (2), height (3), fps (4) }
    MediaFrame { pts (uint64, 1), flags (2), data (bytes, 3), fragment_index (4), fragment_count (5) }
    KeyframeRequest {}
    RotationChanged { orientation (enum, 1) }

Three entry shapes, selected by `input.kind`:

    mediaFormat / mediaFrame / keyframeRequest / rotationChanged: `input.messageHex` is a serialized
      MediaMessage carrying that payload; `expected.summary` is the canonical decoded view and
      `expected.messageSha256` the digest of the re-encoded bytes.
    mediaFrameSequence: `input.messagesHex` is an ordered list of serialized MediaMessage bytes, each a
      MediaFrame fragment. Valid entries carry `expected.reassembledLength`/`reassembledSha256`/`pts`;
      invalid ones carry `expectedError` MALFORMED_FRAME and `localReason` FRAGMENT_VIOLATION, with
      `input.rejectedAtIndex` naming the first fragment that violates the rule.
    mediaFrameLengthPrefix: `input.frameHex` is a bare length prefix rejected by the framing layer.
"""

from __future__ import annotations

import hashlib
from typing import Any

from media_encoding import _field_bytes, _field_varint

MAX_FRAME_BYTES = 1_048_576
CODEC_H264 = 1
ORIENTATION_LANDSCAPE = 2
FLAG_KEYFRAME = 0x1
FLAG_CODEC_CONFIG = 0x2

_MEDIA_MESSAGE_FIELD = {"mediaFormat": 1, "mediaFrame": 2, "keyframeRequest": 3, "rotationChanged": 4}


def _submessage(field_number: int, body: bytes) -> bytes:
    """Encodes a message-typed field; always present even when the body is empty."""
    return _field_bytes(field_number, body) or bytes([(field_number << 3) | 2, 0])


def encode_media_message(kind: str, body: bytes) -> bytes:
    return _submessage(_MEDIA_MESSAGE_FIELD[kind], body)


def encode_media_format(*, codec: int, width: int, height: int, fps: int) -> bytes:
    return _field_varint(1, codec) + _field_varint(2, width) + _field_varint(3, height) + _field_varint(4, fps)


def encode_media_frame(*, pts: int, flags: int, data: bytes, index: int, count: int) -> bytes:
    return (
        _field_varint(1, pts)
        + _field_varint(2, flags)
        + _field_bytes(3, data)
        + _field_varint(4, index)
        + _field_varint(5, count)
    )


def encode_rotation_changed(*, orientation: int) -> bytes:
    return _field_varint(1, orientation)


def _fragment(pts: int, index: int, count: int, data: bytes, flags: int = FLAG_KEYFRAME) -> bytes:
    body = encode_media_frame(pts=pts, flags=flags, data=data, index=index, count=count)
    return encode_media_message("mediaFrame", body)


def _round_trip_vector(vector_id: str, description: str, kind: str, body: bytes, summary: str) -> dict[str, Any]:
    message = encode_media_message(kind, body)
    return {
        "id": vector_id,
        "description": description,
        "input": {"kind": kind, "messageHex": message.hex()},
        "expected": {"summary": summary, "messageSha256": hashlib.sha256(message).hexdigest()},
    }


def _sequence_valid_vector(
    vector_id: str, description: str, pts: int, parts: list[bytes], fragments: list[bytes]
) -> dict[str, Any]:
    reassembled = b"".join(parts)
    return {
        "id": vector_id,
        "description": description,
        "input": {"kind": "mediaFrameSequence", "messagesHex": [f.hex() for f in fragments]},
        "expected": {
            "pts": pts,
            "reassembledLength": len(reassembled),
            "reassembledSha256": hashlib.sha256(reassembled).hexdigest(),
        },
    }


def _sequence_invalid_vector(
    vector_id: str, description: str, fragments: list[bytes], rejected_at_index: int
) -> dict[str, Any]:
    return {
        "id": vector_id,
        "description": description,
        "input": {
            "kind": "mediaFrameSequence",
            "messagesHex": [f.hex() for f in fragments],
            "rejectedAtIndex": rejected_at_index,
        },
        "expectedError": "malformedFrame",
        "closeCode": "MALFORMED_FRAME",
        "localReason": "FRAGMENT_VIOLATION",
    }


def generate_media_frame_encoding_vectors() -> dict[str, Any]:
    """Generates media-connection message and fragmentation vectors."""

    pts = 1_000_000
    sps = bytes.fromhex("0000000167640028acd940780227e5c044000003000400000300f0")
    idr = bytes(range(1, 31))
    parts = [bytes([0xA0 + i] * 4) for i in range(3)]
    three = [_fragment(pts, i, 3, parts[i]) for i in range(3)]
    other = _fragment(pts + 33_333, 0, 3, parts[0])

    vectors: list[dict[str, Any]] = [
        _round_trip_vector(
            "media-frame-keyframe-round-trip",
            "Unfragmented keyframe MediaFrame (fragment 0 of 1) round-tripping to golden bytes on both codecs.",
            "mediaFrame",
            encode_media_frame(pts=pts, flags=FLAG_KEYFRAME, data=idr, index=0, count=1),
            f"pts={pts}|flags=1|dataLength={len(idr)}|index=0|count=1",
        ),
        _round_trip_vector(
            "media-frame-codec-config-round-trip",
            "Codec-config MediaFrame (SPS/PPS bytes, flag 0x2) round-tripping to golden bytes on both codecs.",
            "mediaFrame",
            encode_media_frame(pts=0, flags=FLAG_CODEC_CONFIG, data=sps, index=0, count=1),
            f"pts=0|flags=2|dataLength={len(sps)}|index=0|count=1",
        ),
        _round_trip_vector(
            "media-format-round-trip",
            "MediaFormat H.264 1080x2400 at 60 fps round-tripping to golden bytes on both codecs.",
            "mediaFormat",
            encode_media_format(codec=CODEC_H264, width=1080, height=2400, fps=60),
            "codec=1|width=1080|height=2400|fps=60",
        ),
        _round_trip_vector(
            "keyframe-request-round-trip",
            "KeyframeRequest, an empty payload inside MediaMessage, round-tripping to golden bytes.",
            "keyframeRequest",
            b"",
            "empty",
        ),
        _round_trip_vector(
            "rotation-changed-round-trip",
            "RotationChanged to landscape round-tripping to golden bytes on both codecs.",
            "rotationChanged",
            encode_rotation_changed(orientation=ORIENTATION_LANDSCAPE),
            f"orientation={ORIENTATION_LANDSCAPE}",
        ),
        {
            "id": "media-frame-over-max-frame-size",
            "description": (
                "A media-connection frame with length_prefix = 1 MiB + 1 is rejected by the framing "
                "layer using only the 4 prefix bytes (docs/protocol/SPEC.md #framing-and-envelope, "
                "#media-frame-semantics)."
            ),
            "input": {
                "kind": "mediaFrameLengthPrefix",
                "frameHex": (MAX_FRAME_BYTES + 1).to_bytes(4, "big").hex(),
                "lengthPrefix": MAX_FRAME_BYTES + 1,
            },
            "expectedError": "malformedFrame",
            "closeCode": "MALFORMED_FRAME",
            "localReason": "TOO_LARGE",
        },
        _sequence_valid_vector(
            "media-frame-fragments-three-fragment-access-unit",
            "Three contiguous in-order fragments sharing one pts reassemble to the concatenated data.",
            pts,
            parts,
            three,
        ),
        _sequence_invalid_vector(
            "media-frame-fragments-index-gap",
            "Fragment 0 followed by fragment 2 (index 1 skipped) closes MALFORMED_FRAME/FRAGMENT_VIOLATION.",
            [three[0], three[2]],
            1,
        ),
        _sequence_invalid_vector(
            "media-frame-fragments-count-change",
            "Fragment 0 of 3 followed by fragment 1 of 4 (same pts) closes MALFORMED_FRAME/FRAGMENT_VIOLATION.",
            [three[0], _fragment(pts, 1, 4, parts[1])],
            1,
        ),
        _sequence_invalid_vector(
            "media-frame-fragments-count-nine",
            "A fragment with fragment_count 9 closes MALFORMED_FRAME/FRAGMENT_VIOLATION.",
            [_fragment(pts, 0, 9, parts[0])],
            0,
        ),
        _sequence_invalid_vector(
            "media-frame-fragments-interleaved-pts",
            "Fragment 0 of 3 followed by another pts's fragment 0 closes MALFORMED_FRAME/FRAGMENT_VIOLATION.",
            [three[0], other],
            1,
        ),
    ]
    return {
        "$schema": "./schema.json",
        "category": "media-frame-encoding",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
