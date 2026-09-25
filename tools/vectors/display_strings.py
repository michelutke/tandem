"""Reference sanitizer + generator for protocol/vectors/display-strings.json (E01-24).

Implements `docs/protocol/SPEC.md` §11 ("Untrusted peer strings (display sanitization)")'s
sanitization order exactly, for the three `kind`s it defines (`name`, `title`, `body`), each with
its own default length cap (64 / 256 / 4096 Unicode scalar values):

    1. Decode as UTF-8, replacing invalid sequences with U+FFFD.
    2. Normalize to NFC.
    3. Remove bidirectional-control code points.
    4. Remove C0/C1 control code points, except U+000A (kept in `body`, removed in `name`/`title`).
    5. In a single-line field (`name`/`title`): remove zero-width code points and collapse
       whitespace runs to a single U+0020.
    6. Re-apply NFC.
    7. Truncate to the cap, counting Unicode scalar values and breaking only on a grapheme-cluster
       boundary; append U+2026 if truncation occurred.

Python's standard library has no Unicode extended-grapheme-cluster segmentation (no ICU
dependency here, per `tools/vectors`'s stdlib-only policy), so `_grapheme_clusters` implements the
minimal subset of UAX #29 needed by this module's own vectors: a base code point followed by
combining marks and/or variation selectors, one regional-indicator pair (a "flag" sequence), and a
ZWJ-joined sequence (e.g. an emoji ZWJ sequence). Any vector outside that subset is out of scope
here; per the E01-24 backlog note, this generator's vectors are themselves the cross-platform
tie-breaker, not either platform's ICU/Swift grapheme implementation.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any

CAP_BY_KIND = {"name": 64, "title": 256, "body": 4096}
MULTI_LINE_KINDS = {"body"}

_BIDI_CONTROLS = frozenset(
    {0x200E, 0x200F, 0x061C, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069}
)
_ZERO_WIDTH = frozenset({0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF})

_ZWJ = "‍"
_VARIATION_SELECTORS = frozenset({"︎", "️"})
_ELLIPSIS = "…"

_WHITESPACE_RUN_RE = re.compile(r"\s+")


def _is_c0_or_c1(code_point: int) -> bool:
    # C0 (U+0000-U+001F) and C1 (U+0080-U+009F) control code points, plus DEL (U+007F): all are
    # Unicode general category Cc, and none of them belong in a rendered display string.
    return (0x00 <= code_point <= 0x1F) or (0x7F <= code_point <= 0x9F)


def _is_combining_mark(ch: str) -> bool:
    return unicodedata.category(ch) in ("Mn", "Mc", "Me")


def _is_regional_indicator(ch: str) -> bool:
    return 0x1F1E6 <= ord(ch) <= 0x1F1FF


def _grapheme_clusters(text: str) -> list[str]:
    """Segments `text` (already NFC-normalized) into extended grapheme clusters, per the minimal
    UAX #29 subset documented in this module's docstring."""
    clusters: list[str] = []
    i = 0
    n = len(text)

    def consume_marks() -> None:
        nonlocal i
        while i < n and (_is_combining_mark(text[i]) or text[i] in _VARIATION_SELECTORS):
            i += 1

    while i < n:
        start = i
        i += 1
        consume_marks()

        if _is_regional_indicator(text[start]) and i < n and _is_regional_indicator(text[i]):
            i += 1
            consume_marks()

        while i < n and text[i] == _ZWJ:
            i += 1  # consume the ZWJ itself
            if i >= n:
                break
            i += 1  # consume the base character it joins to this cluster
            consume_marks()

        clusters.append(text[start:i])

    return clusters


def _truncate_grapheme_safe(text: str, cap: int) -> str:
    if len(text) <= cap:
        return text

    kept = []
    count = 0
    for cluster in _grapheme_clusters(text):
        if count + len(cluster) > cap:
            break
        kept.append(cluster)
        count += len(cluster)

    return "".join(kept) + _ELLIPSIS


def sanitize(raw: bytes, kind: str) -> str:
    if kind not in CAP_BY_KIND:
        raise ValueError(f"unknown kind: {kind!r}")

    text = raw.decode("utf-8", errors="replace")
    text = unicodedata.normalize("NFC", text)
    text = "".join(ch for ch in text if ord(ch) not in _BIDI_CONTROLS)

    keep_lf = kind in MULTI_LINE_KINDS
    text = "".join(ch for ch in text if not _is_c0_or_c1(ord(ch)) or (keep_lf and ch == "\n"))

    if kind not in MULTI_LINE_KINDS:
        text = "".join(ch for ch in text if ord(ch) not in _ZERO_WIDTH)
        text = _WHITESPACE_RUN_RE.sub(" ", text)

    text = unicodedata.normalize("NFC", text)

    return _truncate_grapheme_safe(text, CAP_BY_KIND[kind])


# --- manifest generation (E01-24) ---------------------------------------------------------------


def _vector(vector_id: str, description: str, *, raw: bytes, kind: str) -> dict[str, Any]:
    expected = sanitize(raw, kind)
    return {
        "id": vector_id,
        "description": description,
        "input": {"rawUtf8Hex": raw.hex(), "kind": kind},
        "expected": {"sanitized": expected},
    }


def generate_display_string_vectors() -> dict[str, Any]:
    filler_name = "a" * CAP_BY_KIND["name"]
    filler_title = "b" * CAP_BY_KIND["title"]
    filler_body = "c" * CAP_BY_KIND["body"]

    family_zwj_emoji = "\U0001F468‍\U0001F469‍\U0001F467‍\U0001F466"  # man-woman-girl-boy

    vectors = [
        _vector(
            "display-string-rtl-override-stripped-from-name",
            "U+202E (RIGHT-TO-LEFT OVERRIDE) inside a name MUST be removed (step 3, bidi controls).",
            raw=("Mac‮cod.exe").encode("utf-8"),
            kind="name",
        ),
        _vector(
            "display-string-lri-isolate-stripped-from-title",
            "U+2066 (LEFT-TO-RIGHT ISOLATE) inside a title MUST be removed (step 3, bidi controls).",
            raw=("New ⁦message⁩").encode("utf-8"),
            kind="title",
        ),
        _vector(
            "display-string-zwj-removed-from-name",
            "A bare zero-width joiner (U+200D, not part of an emoji ZWJ sequence) inside a name "
            "MUST be removed: step 5's zero-width strip set (U+200B-U+200D, U+2060, U+FEFF) "
            "applies only to single-line fields (name/title).",
            raw=("Mi‍chel").encode("utf-8"),
            kind="name",
        ),
        _vector(
            "display-string-newline-removed-in-name-kept-in-body",
            "The same raw bytes containing a newline: removed from a name (single-line), kept in "
            "a body (multi-line) (step 4).",
            raw=b"line one\nline two",
            kind="name",
        ),
        _vector(
            "display-string-newline-kept-in-body",
            "The same raw bytes as display-string-newline-removed-in-name-kept-in-body, but "
            "rendered as a body (multi-line): the newline MUST be preserved (step 4).",
            raw=b"line one\nline two",
            kind="body",
        ),
        _vector(
            "display-string-nfd-input-normalized-to-nfc",
            "NFD input (e with combining acute accent, two code points) MUST normalize to NFC "
            "(single precomposed code point) at step 2.",
            raw="Café".encode("utf-8"),
            kind="name",
        ),
        _vector(
            "display-string-c1-control-removed",
            "A C1 control code point (U+0085, NEXT LINE) MUST be removed (step 4).",
            raw="Owner\u0085Mac".encode("utf-8"),
            kind="name",
        ),
        _vector(
            "display-string-invalid-utf8-replaced-with-replacement-char",
            "An invalid UTF-8 byte sequence (a lone continuation byte, 0x80) MUST decode with "
            "U+FFFD in its place (step 1), never dropped and never left as raw bytes.",
            raw=b"Mac\x80Book",
            kind="name",
        ),
        _vector(
            "display-string-whitespace-run-collapsed",
            "A run of several whitespace characters in a name MUST collapse to a single U+0020 "
            "(step 5).",
            raw="Mac   mini".encode("utf-8"),
            kind="name",
        ),
        _vector(
            "display-string-exact-cap-name-unchanged",
            "A name exactly at its 64-scalar-value cap MUST be left unchanged: no truncation, no "
            "appended ellipsis.",
            raw=filler_name.encode("ascii"),
            kind="name",
        ),
        _vector(
            "display-string-exact-cap-title-unchanged",
            "A title exactly at its 256-scalar-value cap MUST be left unchanged.",
            raw=filler_title.encode("ascii"),
            kind="title",
        ),
        _vector(
            "display-string-exact-cap-body-unchanged",
            "A body exactly at its 4096-scalar-value cap MUST be left unchanged.",
            raw=filler_body.encode("ascii"),
            kind="body",
        ),
        _vector(
            "display-string-over-cap-name-truncated-with-ellipsis",
            "A name one scalar value over its 64 cap MUST be truncated to 64 and gain an "
            "appended U+2026.",
            raw=(filler_name + "X").encode("ascii"),
            kind="name",
        ),
        _vector(
            "display-string-emoji-zwj-sequence-at-cap-truncated-on-grapheme-boundary",
            "A 4-person emoji ZWJ sequence (man-ZWJ-woman-ZWJ-girl-ZWJ-boy, one extended "
            "grapheme cluster) straddles the 4096-scalar-value body cap: grapheme-safe "
            "truncation (step 7) MUST drop the whole cluster rather than split it, truncating "
            "to the filler prefix before it plus one appended ellipsis.",
            raw=("c" * (CAP_BY_KIND["body"] - 3) + family_zwj_emoji + "trailing").encode("utf-8"),
            kind="body",
        ),
        _vector(
            "display-string-flag-emoji-regional-indicator-pair-not-split",
            "A flag emoji (a 2-code-point regional-indicator pair, one extended grapheme "
            "cluster) straddling the 256-scalar-value title cap MUST NOT be split: the whole "
            "pair is dropped, matching the emoji-ZWJ-sequence case above with a different "
            "grapheme-cluster rule (regional-indicator pairing instead of ZWJ-joining).",
            raw=("b" * (CAP_BY_KIND["title"] - 1) + "\U0001F1E9\U0001F1EA" + "trailing").encode("utf-8"),
            kind="title",
        ),
    ]

    return {
        "$schema": "./schema.json",
        "category": "display-strings",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
