"""pytest suite for protocol/vectors/frame-encoding.json (E01-19 tdd entries)."""

from __future__ import annotations

import hashlib
from pathlib import Path

import frame_encoding as fe
import vector_schema

REPO_ROOT = Path(__file__).resolve().parents[3]
MANIFEST_PATH = REPO_ROOT / "protocol" / "vectors" / "frame-encoding.json"


def _vector(manifest: dict, vector_id: str) -> dict:
    for entry in manifest["vectors"]:
        if entry["id"] == vector_id:
            return entry
    raise KeyError(vector_id)


def _generated_manifest() -> dict:
    return fe.generate_frame_encoding_vectors()


def test_frameVector_exactlyMaxSize_acceptedByReferenceDecoder():
    manifest = _generated_manifest()
    vector = _vector(manifest, "frame-max-size-exact")

    frame_bytes = fe.build_frame_from_vector(vector)

    assert len(frame_bytes) - 4 == fe.MAX_ENVELOPE_BYTES
    assert hashlib.sha256(frame_bytes).hexdigest() == vector["expected"]["frameSha256"]

    result = fe.decode_frame(frame_bytes)

    assert result.accepted
    assert result.channel == fe.CHANNEL_VALUES["CHANNEL_STATUS"]
    assert result.seq == 1
    assert result.ack == 0
    assert result.payload == "ring"


def test_frameVector_oneByteOverMaxSize_rejectedWithMalformedFrameCloseCode():
    manifest = _generated_manifest()
    vector = _vector(manifest, "frame-oversize-plus-one")

    frame_bytes = fe.build_frame_from_vector(vector)
    result = fe.decode_frame(frame_bytes)

    assert not result.accepted
    assert result.close_code == "MALFORMED_FRAME"
    assert result.reason == "TOO_LARGE"
    assert vector["closeCode"] == "MALFORMED_FRAME"
    assert vector["localReason"] == "TOO_LARGE"
    # Only the 4-byte prefix is supplied: a decoder that allocated a buffer before checking the
    # length would be caught reading past the end of this vector's bytes.
    assert len(frame_bytes) == 4


def test_frameVector_truncatedPayload_rejectedWithMalformedFrameCloseCode():
    manifest = _generated_manifest()
    vector = _vector(manifest, "frame-truncated")

    frame_bytes = fe.build_frame_from_vector(vector)
    result = fe.decode_frame(frame_bytes)

    assert not result.accepted
    assert result.close_code == "MALFORMED_FRAME"
    assert result.reason == "TRUNCATED"
    assert vector["closeCode"] == "MALFORMED_FRAME"
    assert vector["localReason"] == "TRUNCATED"


def test_frameVector_zeroLength_rejectedWithMalformedFrameCloseCode():
    manifest = _generated_manifest()
    vector = _vector(manifest, "frame-bad-length-zero")

    frame_bytes = fe.build_frame_from_vector(vector)
    result = fe.decode_frame(frame_bytes)

    assert not result.accepted
    assert result.close_code == "MALFORMED_FRAME"
    assert result.reason == "BAD_LENGTH"
    assert vector["closeCode"] == "MALFORMED_FRAME"
    assert vector["localReason"] == "BAD_LENGTH"


def test_frameVector_unknownChannelEnum_rejectedWithMalformedFrameCloseCode():
    manifest = _generated_manifest()
    vector = _vector(manifest, "frame-unknown-channel")

    frame_bytes = fe.build_frame_from_vector(vector)
    result = fe.decode_frame(frame_bytes)

    assert not result.accepted
    assert result.close_code == "MALFORMED_FRAME"
    assert result.reason == "UNKNOWN_CHANNEL"
    assert vector["closeCode"] == "MALFORMED_FRAME"
    assert vector["localReason"] == "UNKNOWN_CHANNEL"


def test_frameVector_unknownPayloadType_rejectedWithMalformedFrameCloseCode():
    manifest = _generated_manifest()
    vector = _vector(manifest, "frame-unknown-payload-type")

    frame_bytes = fe.build_frame_from_vector(vector)
    result = fe.decode_frame(frame_bytes)

    assert not result.accepted
    assert result.close_code == "MALFORMED_FRAME"
    assert result.reason == "UNKNOWN_PAYLOAD_TYPE"
    assert vector["closeCode"] == "MALFORMED_FRAME"
    assert vector["localReason"] == "UNKNOWN_PAYLOAD_TYPE"


def test_frameVector_badLengthMaxU32_rejectedWithMalformedFrameCloseCode():
    manifest = _generated_manifest()
    vector = _vector(manifest, "frame-bad-length-0xffffffff")

    frame_bytes = fe.build_frame_from_vector(vector)
    result = fe.decode_frame(frame_bytes)

    assert not result.accepted
    assert result.close_code == "MALFORMED_FRAME"
    # 0xFFFFFFFF is > 1 MiB, so SPEC.md's rejection table classifies it as oversize (TOO_LARGE),
    # not a distinct BAD_LENGTH case; BAD_LENGTH is reserved for length_prefix == 0.
    assert result.reason == "TOO_LARGE"
    assert vector["localReason"] == "TOO_LARGE"


def test_frameVector_decodeFailure_rejectedWithMalformedFrameCloseCode():
    manifest = _generated_manifest()
    vector = _vector(manifest, "frame-decode-failed")

    frame_bytes = fe.build_frame_from_vector(vector)
    result = fe.decode_frame(frame_bytes)

    assert not result.accepted
    assert result.close_code == "MALFORMED_FRAME"
    assert result.reason == "DECODE_FAILED"
    assert vector["localReason"] == "DECODE_FAILED"


def test_frameVector_minAndTypicalSize_acceptedByReferenceDecoder():
    manifest = _generated_manifest()

    min_vector = _vector(manifest, "frame-min-size")
    result = fe.decode_frame(fe.build_frame_from_vector(min_vector))
    assert result.accepted
    assert result.payload == "ring"

    typical_vector = _vector(manifest, "frame-typical-size")
    result = fe.decode_frame(fe.build_frame_from_vector(typical_vector))
    assert result.accepted
    assert result.payload == "deviceStatus"
    assert result.seq == 42
    assert result.ack == 41


def test_frameVectorGenerator_runTwice_outputByteIdentical():
    assert _generated_manifest() == _generated_manifest()


def test_frameVectorManifest_committedFile_validatesAgainstSchema():
    assert MANIFEST_PATH.exists(), f"missing committed manifest: {MANIFEST_PATH}"
    manifest = vector_schema.load_manifest(MANIFEST_PATH)
    assert vector_schema.validate_manifest(manifest) == []
    assert manifest["category"] == "frame-encoding"
