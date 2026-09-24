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

## Generating and validating

See `tools/vectors/README.md` for how to run the generator, the pytest suite, and the schema /
regeneration checks that CI (the `protocol` workflow) runs on every change under `protocol/vectors/`
or `tools/vectors/`.

## Authoritativeness

Per E01-16, a vector category is not authoritative until its PR is reviewed and approved: both
platform teams must be able to reproduce the same expected outputs independently before any
downstream issue that consumes a category (E01-17..E01-21) is marked done.
