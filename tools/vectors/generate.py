#!/usr/bin/env python3
"""Reference generator for protocol/vectors/*.json test-vector manifests (E01-16).

This module defines the generator *machinery* only: a category registry, deterministic
JSON rendering, and the write / check / validate operations CI runs against it. Each
downstream vector category (E01-17 SPKI fingerprints, E01-18 pairing proof HMAC, E01-19
frame encoding, E01-20 Bonjour rotating ID, E01-21 QR payload parsing, E01-23a display
strings) registers itself by appending a (filename, generator) pair to CATEGORIES; no
category is registered by E01-16 itself.

Usage:
    python tools/vectors/generate.py             # (re)write every registered category's manifest
    python tools/vectors/generate.py --check      # exit non-zero with a diff if committed
                                                   # manifests differ from a fresh run (CI gate)
    python tools/vectors/generate.py --validate   # exit non-zero if any committed manifest under
                                                   # protocol/vectors/ fails schema.json (CI gate)

Both --check and --validate may be combined with a normal run; each is independent and either
may be passed alone.
"""

from __future__ import annotations

import argparse
import difflib
import json
import sys
from pathlib import Path
from typing import Any, Callable

REPO_ROOT = Path(__file__).resolve().parents[2]
VECTORS_DIR = REPO_ROOT / "protocol" / "vectors"

# Makes `vector_schema` importable regardless of whether this module was run as a script or
# imported (e.g. from tools/vectors/tests/).
sys.path.insert(0, str(Path(__file__).resolve().parent))

from discovery_id import generate_discovery_id_vectors  # noqa: E402 (needs sys.path above)
from display_strings import generate_display_string_vectors  # noqa: E402 (needs sys.path above)
from frame_encoding import generate_frame_encoding_vectors  # noqa: E402 (needs sys.path above)
from pairing_proof import generate_pairing_proof_vectors  # noqa: E402 (needs sys.path above)
from qr_payload import generate_qr_payload_vectors  # noqa: E402 (needs sys.path above)
from spki_fingerprint import generate_spki_fingerprint_vectors  # noqa: E402 (needs sys.path above)

Manifest = dict[str, Any]
CategoryGenerator = Callable[[], Manifest]

# Downstream issues append their (filename, generator) pair here, e.g.:
#   CATEGORIES.append(("spki-fingerprint.json", generate_spki_fingerprint_vectors))
CATEGORIES: list[tuple[str, CategoryGenerator]] = []
CATEGORIES.append(("discovery-id.json", generate_discovery_id_vectors))  # E01-20
CATEGORIES.append(("frame-encoding.json", generate_frame_encoding_vectors))  # E01-19
CATEGORIES.append(("spki-fingerprint.json", generate_spki_fingerprint_vectors))  # E01-17
CATEGORIES.append(("pairing-proof.json", generate_pairing_proof_vectors))  # E01-18
CATEGORIES.append(("qr-payload.json", generate_qr_payload_vectors))  # E01-21
CATEGORIES.append(("display-strings.json", generate_display_string_vectors))  # E01-24


def render(manifest: Manifest) -> str:
    """Deterministic JSON rendering of a manifest: field order is whatever the category
    generator builds (Python dicts preserve insertion order), keys are never re-sorted, and
    the same manifest dict always renders to the same bytes. Generators MUST NOT depend on
    wall-clock time, randomness, hash-order-dependent iteration (e.g. plain `set`), or any
    other non-deterministic input; fixed seeds/inputs are checked into the generator itself.
    """
    return json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=False) + "\n"


def write_manifest(filename: str, manifest: Manifest, *, directory: Path = VECTORS_DIR) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / filename
    path.write_text(render(manifest), encoding="utf-8")
    return path


def generate_all(
    *, categories: list[tuple[str, CategoryGenerator]] | None = None
) -> dict[str, str]:
    """Returns {filename: rendered content} for every registered category, without writing
    anything."""
    return {filename: render(gen()) for filename, gen in (categories if categories is not None else CATEGORIES)}


def check(
    *,
    directory: Path = VECTORS_DIR,
    categories: list[tuple[str, CategoryGenerator]] | None = None,
) -> list[str]:
    """Returns a unified diff per manifest whose committed content differs from a fresh
    generation run. Empty list means every registered category's committed manifest is up to
    date (vacuously true while CATEGORIES is empty)."""
    diffs = []
    for filename, rendered in generate_all(categories=categories).items():
        path = directory / filename
        committed = path.read_text(encoding="utf-8") if path.exists() else ""
        if committed != rendered:
            diff = "".join(
                difflib.unified_diff(
                    committed.splitlines(keepends=True),
                    rendered.splitlines(keepends=True),
                    fromfile=f"committed/{filename}",
                    tofile=f"generated/{filename}",
                )
            )
            diffs.append(diff or f"{filename}: differs\n")
    return diffs


def validate_committed_manifests(*, directory: Path = VECTORS_DIR) -> list[str]:
    """Validates every *.json manifest under `directory` (excluding schema.json) against
    schema.json. Returns a list of "<file>: <error>" strings; empty means every manifest
    (vacuously, zero manifests) is schema-valid."""
    from vector_schema import all_manifest_paths, load_manifest, validate_manifest

    errors = []
    for path in all_manifest_paths(directory):
        manifest = load_manifest(path)
        for message in validate_manifest(manifest):
            errors.append(f"{path.relative_to(REPO_ROOT)}: {message}")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail with a diff instead of writing, if committed manifests are stale",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="fail if any committed manifest under protocol/vectors/ fails schema.json",
    )
    args = parser.parse_args(argv)

    exit_code = 0

    if args.check:
        diffs = check()
        if diffs:
            print(
                "protocol/vectors manifests are out of date; run "
                "`python tools/vectors/generate.py` and commit the result:\n",
                file=sys.stderr,
            )
            for diff in diffs:
                print(diff, file=sys.stderr)
            exit_code = 1
        else:
            print("protocol/vectors manifests are up to date.")

    if args.validate:
        errors = validate_committed_manifests()
        if errors:
            print("protocol/vectors manifests failed schema validation:\n", file=sys.stderr)
            for error in errors:
                print(f"  {error}", file=sys.stderr)
            exit_code = 1
        else:
            print("protocol/vectors manifests validate against schema.json.")

    if not args.check and not args.validate:
        for filename, gen in CATEGORIES:
            write_manifest(filename, gen())
            print(f"wrote {filename}")

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
