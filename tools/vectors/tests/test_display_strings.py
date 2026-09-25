"""pytest suite for protocol/vectors/display-strings.json (E01-24 tdd entries).

Every test below re-derives its expectation directly from `unicodedata` / plain code-point
arithmetic (or, for the two grapheme-cluster-boundary vectors, from presence/absence and length
assertions that do not depend on any particular cluster-segmentation algorithm) instead of calling
`display_strings.sanitize`, so a shared bug between the generator and this suite would still be
caught (grapheme segmentation differs across ICU/Swift versions too — see the backlog note on
E01-24: the vector, not either platform or this generator, is the tie-breaker).
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any

import vector_schema

MANIFEST_PATH = vector_schema.VECTORS_DIR / "display-strings.json"


def _load_manifest() -> dict[str, Any]:
    return vector_schema.load_manifest(MANIFEST_PATH)


def _vectors_by_id(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {v["id"]: v for v in manifest["vectors"]}


def _raw_text(vector: dict[str, Any]) -> str:
    return bytes.fromhex(vector["input"]["rawUtf8Hex"]).decode("utf-8", errors="replace")


def test_displayStringVector_rightToLeftOverride_stripped():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["display-string-rtl-override-stripped-from-name"]

    text = unicodedata.normalize("NFC", _raw_text(vector))
    assert "‮" in text  # the raw input really does contain the override we're stripping
    assert "‮" not in vector["expected"]["sanitized"]
    assert vector["expected"]["sanitized"] == "Maccod.exe"


def test_displayStringVector_zeroWidthJoinerInName_removed():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["display-string-zwj-removed-from-name"]

    text = _raw_text(vector)
    assert "‍" in text
    assert "‍" not in vector["expected"]["sanitized"]
    assert vector["expected"]["sanitized"] == "Michel"


def test_displayStringVector_newlineInName_removedButKeptInBody():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)

    name_vector = by_id["display-string-newline-removed-in-name-kept-in-body"]
    body_vector = by_id["display-string-newline-kept-in-body"]

    assert name_vector["input"]["rawUtf8Hex"] == body_vector["input"]["rawUtf8Hex"]
    assert "\n" not in name_vector["expected"]["sanitized"]
    assert "\n" in body_vector["expected"]["sanitized"]
    assert body_vector["expected"]["sanitized"] == "line one\nline two"


def test_displayStringVector_nfdInput_normalizedToNfc():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["display-string-nfd-input-normalized-to-nfc"]

    raw_text = _raw_text(vector)
    assert not unicodedata.is_normalized("NFC", raw_text)  # input really is decomposed (NFD)

    reference_nfc = unicodedata.normalize("NFC", raw_text)
    assert vector["expected"]["sanitized"] == reference_nfc
    assert unicodedata.is_normalized("NFC", vector["expected"]["sanitized"])


def test_displayStringVector_invalidUtf8_replacedWithReplacementChar():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["display-string-invalid-utf8-replaced-with-replacement-char"]

    raw = bytes.fromhex(vector["input"]["rawUtf8Hex"])
    reference = raw.decode("utf-8", errors="replace")

    assert "�" in reference
    assert vector["expected"]["sanitized"] == reference


def test_displayStringVector_whitespaceRun_collapsed():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["display-string-whitespace-run-collapsed"]

    raw_text = _raw_text(vector)
    reference = re.sub(r"\s+", " ", raw_text)

    assert "   " in raw_text
    assert vector["expected"]["sanitized"] == reference
    assert "  " not in vector["expected"]["sanitized"]


def test_displayStringVector_exactCapInput_leftUnchanged():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)

    caps = {"display-string-exact-cap-name-unchanged": 64, "display-string-exact-cap-title-unchanged": 256, "display-string-exact-cap-body-unchanged": 4096}
    for vector_id, cap in caps.items():
        vector = by_id[vector_id]
        raw_text = _raw_text(vector)
        assert len(raw_text) == cap
        assert vector["expected"]["sanitized"] == raw_text
        assert "…" not in vector["expected"]["sanitized"]


def test_displayStringVector_overCapInput_truncatedWithEllipsis():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["display-string-over-cap-name-truncated-with-ellipsis"]

    raw_text = _raw_text(vector)
    assert len(raw_text) == 65

    sanitized = vector["expected"]["sanitized"]
    assert len(sanitized) == 65  # 64 kept scalar values + 1 appended ellipsis
    assert sanitized.endswith("…")
    assert sanitized[:-1] == raw_text[:64]


def test_displayStringVector_emojiSequenceAtCap_truncatedOnGraphemeBoundary():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["display-string-emoji-zwj-sequence-at-cap-truncated-on-grapheme-boundary"]

    sanitized = vector["expected"]["sanitized"]
    cap = 4096

    # The straddling cluster is MAN U+200D WOMAN U+200D GIRL U+200D BOY: independently of any
    # particular grapheme-segmentation algorithm, a grapheme-safe truncation must never emit a
    # *partial* cluster, so none of the ZWJ or the four emoji code points may appear at all.
    for forbidden in ("‍", "\U0001F468", "\U0001F469", "\U0001F467", "\U0001F466"):
        assert forbidden not in sanitized

    assert sanitized.endswith("…")
    assert len(sanitized) == (cap - 3) + 1  # filler prefix kept, whole 7-code-point cluster dropped
    assert sanitized[:-1] == "c" * (cap - 3)


def test_displayStringVector_flagEmojiRegionalIndicatorPair_notSplit():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["display-string-flag-emoji-regional-indicator-pair-not-split"]

    sanitized = vector["expected"]["sanitized"]
    cap = 256

    # A flag sequence is exactly two regional-indicator code points; a grapheme-safe truncation
    # must drop both or neither, never just one.
    for forbidden in ("\U0001F1E9", "\U0001F1EA"):
        assert forbidden not in sanitized

    assert sanitized.endswith("…")
    assert len(sanitized) == (cap - 1) + 1
    assert sanitized[:-1] == "b" * (cap - 1)


def test_displayStringVectorGenerator_runTwice_outputByteIdentical():
    import display_strings as ds

    assert ds.generate_display_string_vectors() == ds.generate_display_string_vectors()


def test_displayStringVectorManifest_committedFile_validatesAgainstSchema():
    assert MANIFEST_PATH.exists(), f"missing committed manifest: {MANIFEST_PATH}"
    manifest = vector_schema.load_manifest(MANIFEST_PATH)
    assert vector_schema.validate_manifest(manifest) == []
    assert manifest["category"] == "display-strings"
