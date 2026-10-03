"""pytest suite for protocol/vectors/phone-normalization.json (E51-06 tdd entries)."""

from __future__ import annotations

import re
from typing import Any

import vector_schema

MANIFEST_PATH = vector_schema.VECTORS_DIR / "phone-normalization.json"
E164_RE = re.compile(r"^\+[1-9][0-9]{6,14}$")


def _load_manifest() -> dict[str, Any]:
    return vector_schema.load_manifest(MANIFEST_PATH)


def test_phoneNormalizationVectors_schema_validatesAgainstVectorFormat():
    manifest = _load_manifest()
    assert vector_schema.validate_manifest(manifest) == []
    for vector in manifest["vectors"]:
        assert set(vector["input"]) == {"raw", "region"}
        assert len(vector["input"]["region"]) == 2
        assert "expectedError" not in vector


def test_phoneNormalizationVectors_validCases_areE164():
    valid = [v for v in _load_manifest()["vectors"] if v["expected"]["e164"] is not None]
    assert len(valid) >= 10
    for vector in valid:
        assert E164_RE.match(vector["expected"]["e164"]), vector["id"]


def test_phoneNormalizationVectors_invalidCases_coverNullKinds():
    ids = {v["id"] for v in _load_manifest()["vectors"] if v["expected"]["e164"] is None}
    assert any("short-code" in i for i in ids)
    assert any("alphanumeric" in i for i in ids)
    assert any("empty" in i for i in ids)
    assert any("invalid" in i for i in ids)
