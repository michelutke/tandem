"""pytest suite for protocol/vectors/schema.json validation (E01-16 tdd entries)."""

from __future__ import annotations

import copy

import vector_schema

VALID_MANIFEST = {
    "category": "example",
    "generatedBy": "tools/vectors/generate.py",
    "vectors": [
        {
            "id": "example-01",
            "description": "a positive example vector",
            "input": {"value": 1},
            "expected": {"value": 2},
        },
        {
            "id": "example-02",
            "description": "a negative example vector",
            "input": {"value": -1},
            "expectedError": "valueOutOfRange",
            "closeCode": "MALFORMED_FRAME",
            "localReason": "BAD_LENGTH",
        },
    ],
}


def entry(**overrides):
    base = {
        "id": "example-03",
        "description": "a synthetic vector entry",
        "input": {"value": 0},
    }
    base.update(overrides)
    return base


def manifest_with(vector_entry):
    manifest = copy.deepcopy(VALID_MANIFEST)
    manifest["vectors"] = [vector_entry]
    return manifest


def test_vectorSchema_validPositiveManifest_accepted():
    assert vector_schema.validate_manifest(VALID_MANIFEST) == []


def test_vectorSchema_entryWithBothExpectedAndExpectedError_rejected():
    bad = manifest_with(entry(expected={"value": 1}, expectedError="valueOutOfRange"))
    assert vector_schema.validate_manifest(bad) != []


def test_vectorSchema_entryWithNeitherExpectedNorExpectedError_rejected():
    bad = manifest_with(entry())
    assert vector_schema.validate_manifest(bad) != []


def test_vectorSchema_closeCodeWithoutExpectedError_rejected():
    bad = manifest_with(entry(expected={"value": 1}, closeCode="MALFORMED_FRAME"))
    assert vector_schema.validate_manifest(bad) != []


def test_vectorSchema_unknownCloseCode_rejected():
    bad = manifest_with(entry(expectedError="valueOutOfRange", closeCode="NOT_A_REAL_CODE"))
    assert vector_schema.validate_manifest(bad) != []


def test_vectorSchema_missingGeneratedBy_rejected():
    bad = copy.deepcopy(VALID_MANIFEST)
    del bad["generatedBy"]
    assert vector_schema.validate_manifest(bad) != []


def test_vectorSchema_wrongGeneratedByValue_rejected():
    bad = copy.deepcopy(VALID_MANIFEST)
    bad["generatedBy"] = "hand-edited"
    assert vector_schema.validate_manifest(bad) != []


def test_vectorSchema_duplicateIdWithinManifest_notEnforcedBySchemaAlone():
    # JSON Schema 2020-12 has no first-class "unique by field" constraint; duplicate `id`
    # detection is a generator-level concern (each category generator is responsible for
    # not emitting duplicate ids), not a schema.json constraint.
    manifest = copy.deepcopy(VALID_MANIFEST)
    manifest["vectors"].append(copy.deepcopy(VALID_MANIFEST["vectors"][0]))
    assert vector_schema.validate_manifest(manifest) == []


def test_vectorManifests_allCategories_validateAgainstSchema():
    errors = []
    for path in vector_schema.all_manifest_paths():
        manifest = vector_schema.load_manifest(path)
        errors.extend(f"{path.name}: {e}" for e in vector_schema.validate_manifest(manifest))
    assert errors == []
