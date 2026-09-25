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

E01-16 defines the file format and generator machinery only, with an empty category registry.
Each downstream vector-category issue (E01-17 SPKI fingerprints, E01-18 pairing proof HMAC,
E01-19 frame encoding, E01-20 Bonjour rotating ID, E01-21 QR payload parsing, E01-24 display
strings) adds its own generator function and registers it with
`CATEGORIES.append(("<category>.json", generate_fn))`.
E01-20 registers `discovery-id.json` via `discovery_id.generate_discovery_id_vectors`.
E01-19 registers `frame-encoding.json` via `frame_encoding.generate_frame_encoding_vectors`; that
module also doubles as a minimal reference protobuf encoder/decoder for `Envelope` frames (see its
module docstring and `protocol/vectors/README.md`'s `frame-encoding.json` section).
E01-17 registers `spki-fingerprint.json` via `spki_fingerprint.generate_spki_fingerprint_vectors`;
that module also implements minimal stdlib-only P-256 scalar multiplication and ASN.1 DER encoding
(see its module docstring).
E01-21 registers `qr-payload.json` via `qr_payload.generate_qr_payload_vectors`; that module also
doubles as the reference parser (`parse_pair_uri`) for the `tandem://pair` QR grammar.
E01-24 registers `display-strings.json` via
`display_strings.generate_display_string_vectors`; that module also doubles as the reference
sanitizer (`sanitize`) for SPEC.md's untrusted-peer-string rule, including a minimal
grapheme-cluster segmenter (see its module docstring).

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
- `discovery_id.py` — E01-20 `discovery-id` category generator (Bonjour rotating id).
- `frame_encoding.py` — E01-19 `frame-encoding.json` generator plus its reference frame
  encoder/decoder.
- `spki_fingerprint.py` — E01-17 `spki-fingerprint.json` generator plus its stdlib-only P-256
  scalar multiplication and ASN.1 DER encoding.
- `qr_payload.py` — E01-21 `qr-payload.json` generator plus its reference `tandem://pair`
  QR-payload parser.
- `display_strings.py` — E01-24 `display-strings.json` generator plus its reference
  untrusted-peer-string sanitizer.
- `requirements.txt` — pinned `jsonschema` / `pytest` versions.
- `tests/` — pytest suite (`test_generate.py`, `test_schema.py`, `test_discovery_id.py`,
  `test_frame_encoding.py`, `test_spki_fingerprint.py`, `test_qr_payload.py`,
  `test_display_strings.py`).

## CI

The `protocol` GitHub Actions workflow runs, on any change under `protocol/vectors/` or
`tools/vectors/`: `pytest tools/vectors/tests`, `python tools/vectors/generate.py --validate`,
and `python tools/vectors/generate.py --check`.
