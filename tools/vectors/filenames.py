"""Reference sanitizer + generator for protocol/vectors/filenames.json (E40-02).

Implements `docs/protocol/SPEC.md` `#filename-sanitization` exactly: the ordered rule a receiver
applies to an incoming `FileOffer.name` before using it as a destination filename.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any

MAX_FILENAME_BYTES = 255
INVALID_NAME = "invalidName"

_BIDI_CONTROLS = frozenset(range(0x202A, 0x202F)) | frozenset(range(0x2066, 0x206A))
_WINDOWS_RESERVED_STEMS = frozenset(
    {"CON", "PRN", "AUX", "NUL"}
    | {f"COM{n}" for n in range(1, 10)}
    | {f"LPT{n}" for n in range(1, 10)}
)
_SEPARATORS_RE = re.compile(r"[/\\]")


def _replace_unsafe(ch: str) -> str:
    code_point = ord(ch)
    if code_point < 0x20 or code_point == 0x7F or ch == ":":
        return "_"
    return ch


def _split_extension(name: str) -> tuple[str, str]:
    dot = name.rfind(".")
    if dot <= 0:
        return name, ""
    return name[:dot], name[dot:]


def _truncate_to_bytes(name: str) -> str:
    if len(name.encode("utf-8")) <= MAX_FILENAME_BYTES:
        return name

    stem, extension = _split_extension(name)
    budget = MAX_FILENAME_BYTES - len(extension.encode("utf-8"))
    if budget < 1:
        stem, extension, budget = name, "", MAX_FILENAME_BYTES

    kept: list[str] = []
    used = 0
    for ch in stem:
        size = len(ch.encode("utf-8"))
        if used + size > budget:
            break
        kept.append(ch)
        used += size
    return "".join(kept) + extension


def sanitize(name: str, transfer_id: str) -> str | None:
    """Returns the destination filename, or None when the offer MUST be rejected INVALID_NAME."""
    if "\x00" in name:
        return None

    last_component = _SEPARATORS_RE.split(name)[-1]
    text = unicodedata.normalize("NFC", last_component)
    text = "".join(ch for ch in text if ord(ch) not in _BIDI_CONTROLS)
    text = "".join(_replace_unsafe(ch) for ch in text)
    text = text.lstrip(".")

    if not text:
        return f"file-{transfer_id[:8]}"

    if text.split(".", 1)[0].upper() in _WINDOWS_RESERVED_STEMS:
        text = f"_{text}"

    return _truncate_to_bytes(text)


# --- manifest generation (E40-02) ---------------------------------------------------------------

TRANSFER_ID = "1a2b3c4d5e6f4a7b8c9d0e1f2a3b4c5d"


def _vector(vector_id: str, description: str, *, name: str, transfer_id: str = TRANSFER_ID) -> dict[str, Any]:
    result = sanitize(name, transfer_id)
    vector: dict[str, Any] = {
        "id": vector_id,
        "description": description,
        "input": {"rawUtf8Hex": name.encode("utf-8").hex(), "transferId": transfer_id},
    }
    if result is None:
        vector["expectedError"] = INVALID_NAME
    else:
        vector["expected"] = {"filename": result}
    return vector


def generate_filename_vectors() -> dict[str, Any]:
    vectors = [
        _vector(
            "filename-parent-traversal-reduced-to-last-component",
            "../../etc/passwd keeps only the last component after splitting on '/' and '\\'.",
            name="../../etc/passwd",
        ),
        _vector(
            "filename-absolute-posix-path-reduced-to-last-component",
            "An absolute POSIX path keeps only its last component.",
            name="/Users/x/secret.txt",
        ),
        _vector(
            "filename-windows-path-reduced-to-last-component",
            "A Windows path with a drive letter and backslashes keeps only its last component.",
            name="C:\\Windows\\evil.exe",
        ),
        _vector(
            "filename-nul-byte-rejected-invalid-name",
            "U+0000 anywhere in the name rejects the offer with INVALID_NAME before any other step.",
            name="a\x00b.txt",
        ),
        _vector(
            "filename-leading-dot-stripped",
            "Leading dots are stripped so the file is never hidden.",
            name=".bashrc",
        ),
        _vector(
            "filename-double-dot-replaced-with-transfer-id-name",
            "'..' is all dots, so the name becomes file-<first 8 chars of the transfer id>.",
            name="..",
        ),
        _vector(
            "filename-empty-replaced-with-transfer-id-name",
            "An empty name becomes file-<first 8 chars of the transfer id>.",
            name="",
        ),
        _vector(
            "filename-trailing-separator-replaced-with-transfer-id-name",
            "A trailing separator leaves an empty last component.",
            name="photos/",
        ),
        _vector(
            "filename-windows-reserved-stem-prefixed",
            "A Windows-reserved stem (CON) is prefixed with '_'.",
            name="CON",
        ),
        _vector(
            "filename-windows-reserved-stem-lowercase-with-extension-prefixed",
            "Windows-reserved stems match case-insensitively and regardless of extension.",
            name="nul.txt",
        ),
        _vector(
            "filename-windows-reserved-lookalike-unchanged",
            "A stem that merely starts with a reserved name (CONSOLE) is not reserved.",
            name="CONSOLE.txt",
        ),
        _vector(
            "filename-nfd-normalized-to-nfc",
            "NFD input (e + U+0301) is normalized to NFC (U+00E9).",
            name="e\u0301.txt",
        ),
        _vector(
            "filename-bidi-override-removed",
            "U+202E (RIGHT-TO-LEFT OVERRIDE) is removed so the extension cannot be disguised.",
            name="invoice\u202efdp.exe",
        ),
        _vector(
            "filename-bidi-isolate-removed",
            "U+2066-U+2069 (isolates) are removed.",
            name="re\u2066po\u2069rt.pdf",
        ),
        _vector(
            "filename-colon-and-control-characters-replaced",
            "':' , C0 controls and U+007F are replaced with '_'.",
            name="a:b\tc\x7fd.txt",
        ),
        _vector(
            "filename-long-ascii-stem-truncated-keeping-extension",
            "300 x 'a' + '.pdf' truncates the stem to 251 bytes so the whole name is 255 bytes.",
            name="a" * 300 + ".pdf",
        ),
        _vector(
            "filename-long-multibyte-stem-truncated-on-code-point-boundary",
            "200 x 'é' + '.jpg' truncates to 125 'é' (250 bytes) + '.jpg' (254 bytes), never "
            "splitting a code point.",
            name="\u00e9" * 200 + ".jpg",
        ),
    ]
    return {
        "$schema": "./schema.json",
        "category": "filenames",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
