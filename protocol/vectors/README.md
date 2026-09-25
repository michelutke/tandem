protocol/vectors — E01-16: cross-platform test vectors (JSON manifests plus binary fixtures)
consumed by tools/conformance.

## Format

Every manifest is a single JSON file directly under this directory, produced by
`tools/vectors/generate.py` and validated against [`schema.json`](schema.json) (JSON Schema
2020-12). One manifest per vector category, named `<category>.json` (e.g.
`spki-fingerprint.json`, E01-17).

Top-level shape:

```json
{
  "$schema": "./schema.json",
  "category": "example",
  "generatedBy": "tools/vectors/generate.py",
  "vectors": [ /* vectorEntry, at least one */ ]
}
```

Each `vectors[]` entry has:

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique within the manifest, stable across regenerations. |
| `description` | yes | Human-readable summary of what the vector exercises. |
| `input` | yes | Category-defined input. Free-form JSON. |
| `expected` | exactly one of `expected` / `expectedError` | Positive-case expected output. |
| `expectedError` | exactly one of `expected` / `expectedError` | Stable, camelCase error name for a negative case (e.g. `unsupportedPointEncoding`). |
| `closeCode` | only with `expectedError` | One of the frozen close-code names from `docs/protocol/SPEC.md` `#errors-and-close-codes` (E01-05), present only when the negative case closes a connection. |
| `localReason` | only with `expectedError` | Category-defined local diagnostic reason grouped under `closeCode` (e.g. `TOO_LARGE` under `MALFORMED_FRAME`); never sent on the wire (SPEC.md §3/§5). |

A manifest entry with both `expected` and `expectedError`, or with neither, fails schema
validation — this is enforced by `schema.json`'s `oneOf`, not by generator convention alone.

### Binary / not-text-safe fixtures

Where a vector's payload is not text-safe to inline (e.g. raw DER, non-UTF-8 bytes), the
generator writes it to `protocol/vectors/fixtures/<category>/<name>.bin` and the manifest
entry's `input`/`expected` references it by a `*File` key holding that path relative to this
directory, instead of inlining the bytes. Everything that *is* text-safe (hex strings,
base64url, UTF-8 with an explicit encoding note) is inlined directly so the manifest stays
diffable.

### Compact recipes for large payloads

A vector whose wire bytes are large (e.g. `frame-encoding.json`'s exactly-1-MiB `Envelope`) is
not inlined as a hex blob and does not get a committed binary fixture either, to avoid bloating
the repo with a megabyte-scale file that carries no information beyond its size. Instead its
`input` is an `envelopeRecipe` — a small, human-readable description (channel/seq/ack, the real
payload, and a `filler` field: an unrecognized field number carrying `fillLength` repeats of a
single `fillByte`) that a generator function reconstructs byte-for-byte
(`tools/vectors/frame_encoding.py`'s `build_envelope_from_recipe`/`solve_filler`), together with
an `envelopeLength` and (in `expected`) a `frameSha256` so an independent implementation can
verify it reconstructed the identical bytes without either side committing them.

## Generating and validating

See `tools/vectors/README.md` for how to run the generator, the pytest suite, and the schema /
regeneration checks that CI (the `protocol` workflow) runs on every change under `protocol/vectors/`
or `tools/vectors/`.

## Categories

### `frame-encoding.json` (E01-19)

Frame-level valid/invalid vectors for SPEC.md `#framing-and-envelope`'s `frame = length_prefix
envelope_bytes` format and its rejection-cases table. Each entry's `input.frameHex` (or, for the
1-MiB vector, `input.envelopeRecipe` — see "Compact recipes" above) is the exact bytes a receiver
sees on the wire, including the 4-byte big-endian `length_prefix`; `input.lengthPrefix` and
`input.suppliedEnvelopeLength` restate the claimed vs. actually-delivered envelope byte counts for
human review. Valid entries' `expected` gives the decoded `channel`/`seq`/`ack`/`payload`; invalid
entries use `expectedError: "malformedFrame"` with `closeCode: "MALFORMED_FRAME"` and one of the
`localReason`s from SPEC.md's table (`TOO_LARGE`, `BAD_LENGTH`, `TRUNCATED`, `DECODE_FAILED`,
`UNKNOWN_CHANNEL`, `UNKNOWN_PAYLOAD_TYPE`).

Two encodings were not fully pinned down by SPEC.md/decisions.md at the wire-byte level and were
chosen here, following SPEC.md's prose definitions:

- **Unknown channel**: `channel` (field 1) set to `99`, a value the varint wire format accepts
  but that is outside the nine enumerated `Channel` values (0-9) — an otherwise well-formed
  Envelope.
- **Unknown payload type**: the `oneof payload` left unset by omitting fields 20 (`device_status`)
  and 21 (`ring`) entirely and instead writing field 25 — a number inside `envelope.proto`'s
  `reserved 22 to 29` status.proto range, not yet assigned to any payload. A protobuf-lite
  decoder treats an unrecognized field number as an ordinary skippable unknown field regardless
  of whether the `.proto` marks that range `reserved`; the oneof stays unset, matching SPEC.md's
  "the `oneof payload` is unset, or set to a payload type this receiver's protocol version does
  not define."

`frame-oversize-plus-one` and `frame-bad-length-0xffffffff` both supply only the 4-byte prefix (no
payload bytes at all), per the E01-19 acceptance criterion that a decoder allocating a buffer
before checking `length_prefix` would read past the end of the vector.

## Authoritativeness

Per E01-16, a vector category is not authoritative until its PR is reviewed and approved: both
platform teams must be able to reproduce the same expected outputs independently before any
downstream issue that consumes a category (E01-17..E01-21) is marked done.
