"""pytest suite for tools/vectors/generate.py (E01-16 tdd entries)."""

from __future__ import annotations

import generate

SAMPLE_MANIFEST = {
    "$schema": "./schema.json",
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


def test_vectorGenerator_runTwice_outputByteIdentical():
    first = generate.render(SAMPLE_MANIFEST)
    second = generate.render(SAMPLE_MANIFEST)
    assert first == second


def test_vectorGenerator_runTwice_writtenFilesByteIdentical(tmp_path):
    def example_category():
        return SAMPLE_MANIFEST

    categories = [("example.json", example_category)]

    generate.write_manifest("example.json", example_category(), directory=tmp_path)
    first_bytes = (tmp_path / "example.json").read_bytes()

    generate.write_manifest("example.json", example_category(), directory=tmp_path)
    second_bytes = (tmp_path / "example.json").read_bytes()

    assert first_bytes == second_bytes
    assert generate.check(directory=tmp_path, categories=categories) == []


def test_vectorRegenerationCheck_noCategoriesRegistered_noDiffs(tmp_path):
    assert generate.check(directory=tmp_path, categories=[]) == []


def test_vectorRegenerationCheck_committedVectorEdited_jobFailsShowingDiff(tmp_path):
    def example_category():
        return SAMPLE_MANIFEST

    categories = [("example.json", example_category)]
    generate.write_manifest("example.json", example_category(), directory=tmp_path)

    # Simulate a manually hand-edited committed vector drifting from the generator's output.
    (tmp_path / "example.json").write_text(
        '{\n  "category": "example",\n  "generatedBy": "tools/vectors/generate.py",\n  "vectors": []\n}\n',
        encoding="utf-8",
    )

    diffs = generate.check(directory=tmp_path, categories=categories)

    assert len(diffs) == 1
    assert "example.json" in diffs[0]
    assert "-  \"vectors\": []" in diffs[0] or "+  \"vectors\": [" in diffs[0]


def test_vectorRegenerationCheck_missingCommittedFile_reportedAsDiff(tmp_path):
    def example_category():
        return SAMPLE_MANIFEST

    diffs = generate.check(directory=tmp_path, categories=[("example.json", example_category)])

    assert len(diffs) == 1
    assert "example.json" in diffs[0]
