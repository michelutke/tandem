tools/vectors — E01-16: Python reference generator and pytest suite producing protocol/vectors
fixtures.

## Setup

```sh
cd tools/vectors
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

`.venv/` is gitignored; recreate it any time with the commands above. Dependencies are pinned in
`requirements.txt` (`jsonschema`, `pytest`).

## Running

From `tools/vectors` with the venv active:

```sh
pytest tests -q                 # unit tests for the generator + schema machinery
python generate.py              # (re)write every registered category's manifest
python generate.py --check      # fail with a diff if committed manifests are stale
python generate.py --validate   # fail if any committed manifest fails schema.json
```

`generate.py`'s category registry (`CATEGORIES` in `generate.py`) starts empty — E01-16 defines
the file format and generator machinery only. Each downstream vector-category issue (E01-17 SPKI
fingerprints, E01-18 pairing proof HMAC, E01-19 frame encoding, E01-20 Bonjour rotating ID, E01-21
QR payload parsing) adds its own generator function and registers it with
`CATEGORIES.append(("<category>.json", generate_fn))`. `frame_encoding.py` (E01-19) is the first:
it also doubles as a minimal reference protobuf encoder/decoder for `Envelope` frames (see its
module docstring and `protocol/vectors/README.md`'s `frame-encoding.json` section), used by
`tools/vectors/tests/test_frame_encoding.py` to check every generated vector decodes to the
outcome its manifest entry declares.

## Determinism

Every category generator function MUST be a pure function of its fixed, checked-in
seeds/inputs: no wall-clock time, no unseeded randomness, no hash-order-dependent iteration.
`python generate.py` run twice must always produce byte-identical output
(`test_vectorGenerator_runTwice_outputByteIdentical`); CI's `--check` step enforces this against
the committed manifests, catching hand-edits as well as generator non-determinism.

## Files

- `generate.py` — category registry, deterministic JSON rendering, `--check` / `--validate` CLI.
- `vector_schema.py` — thin `jsonschema` wrapper shared by `generate.py --validate` and the
  pytest suite.
- `frame_encoding.py` — E01-19 `frame-encoding.json` generator plus its reference frame
  encoder/decoder.
- `requirements.txt` — pinned `jsonschema` / `pytest` versions.
- `tests/` — pytest suite (`test_generate.py`, `test_schema.py`, `test_frame_encoding.py`).

## CI

The `protocol` GitHub Actions workflow runs, on any change under `protocol/vectors/` or
`tools/vectors/`: `pytest tools/vectors/tests`, `python tools/vectors/generate.py --validate`,
and `python tools/vectors/generate.py --check`.
