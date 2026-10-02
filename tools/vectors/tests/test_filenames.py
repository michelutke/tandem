"""pytest suite for protocol/vectors/filenames.json (E40-02 tdd entries)."""

from __future__ import annotations

from typing import Any

import vector_schema

MANIFEST_PATH = vector_schema.VECTORS_DIR / "filenames.json"
TRANSFER_ID = "1a2b3c4d5e6f4a7b8c9d0e1f2a3b4c5d"

REQUIRED_CASES = {
    "../../etc/passwd": "passwd",
    "/Users/x/secret.txt": "secret.txt",
    "C:\\Windows\\evil.exe": "evil.exe",
    ".bashrc": "bashrc",
    "..": "file-1a2b3c4d",
    "": "file-1a2b3c4d",
    "CON": "_CON",
    "nul.txt": "_nul.txt",
    "e\u0301.txt": "\u00e9.txt",
    "invoice\u202efdp.exe": "invoicefdp.exe",
    "a" * 300 + ".pdf": "a" * 251 + ".pdf",
    "\u00e9" * 200 + ".jpg": "\u00e9" * 125 + ".jpg",
}


def _load_manifest() -> dict[str, Any]:
    return vector_schema.load_manifest(MANIFEST_PATH)


def _name(vector: dict[str, Any]) -> str:
    return bytes.fromhex(vector["input"]["rawUtf8Hex"]).decode("utf-8")


def test_filenameVectors_schemaValidation_everyCaseHasInputAndExpected():
    manifest = _load_manifest()
    assert vector_schema.validate_manifest(manifest) == []
    for vector in manifest["vectors"]:
        assert "rawUtf8Hex" in vector["input"]
        assert vector["input"]["transferId"]
        assert ("expected" in vector) != ("expectedError" in vector)


def test_filenameVectors_requiredCases_allPresentWithExpectedOutput():
    actual = {
        _name(v): v["expected"]["filename"]
        for v in _load_manifest()["vectors"]
        if "expected" in v and v["input"]["transferId"] == TRANSFER_ID
    }
    for name, expected in REQUIRED_CASES.items():
        assert actual[name] == expected


def test_filenameVectors_nulByteCase_expectsInvalidName():
    nul_vectors = [v for v in _load_manifest()["vectors"] if "\x00" in _name(v)]
    assert nul_vectors
    for vector in nul_vectors:
        assert vector["expectedError"] == "invalidName"
    assert "a\x00b.txt" in {_name(v) for v in nul_vectors}


def test_filenameVectors_expectedLengths_withinFileSystemLimit():
    for vector in _load_manifest()["vectors"]:
        if "expected" in vector:
            assert 0 < len(vector["expected"]["filename"].encode("utf-8")) <= 255
