"""Schema-validation helpers for protocol/vectors manifests (E01-16).

Wraps `jsonschema` so both generate.py and the pytest suite validate against the single
checked-in protocol/vectors/schema.json (JSON Schema 2020-12).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import jsonschema

REPO_ROOT = Path(__file__).resolve().parents[2]
VECTORS_DIR = REPO_ROOT / "protocol" / "vectors"
SCHEMA_PATH = VECTORS_DIR / "schema.json"


def load_schema(schema_path: Path = SCHEMA_PATH) -> dict[str, Any]:
    return json.loads(schema_path.read_text(encoding="utf-8"))


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _validator(schema_path: Path = SCHEMA_PATH) -> jsonschema.protocols.Validator:
    schema = load_schema(schema_path)
    validator_cls = jsonschema.validators.validator_for(schema)
    validator_cls.check_schema(schema)
    return validator_cls(schema)


def validate_manifest(manifest: dict[str, Any], *, schema_path: Path = SCHEMA_PATH) -> list[str]:
    """Returns a list of human-readable validation error strings; empty means the manifest is
    schema-valid."""
    errors = sorted(_validator(schema_path).iter_errors(manifest), key=lambda e: list(e.path))
    return [f"{'/'.join(str(p) for p in e.path) or '<root>'}: {e.message}" for e in errors]


def all_manifest_paths(directory: Path = VECTORS_DIR) -> list[Path]:
    """Every committed vector manifest under `directory`, i.e. every *.json file except the
    schema itself."""
    if not directory.exists():
        return []
    return sorted(p for p in directory.glob("*.json") if p.name != "schema.json")
