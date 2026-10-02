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

### `spki-fingerprint.json` (E01-17)

Vectors for SPEC.md `#handshake-and-tls-profile`'s leaf-key check and verify-callback fingerprint
step: SHA-256 over a peer leaf certificate's DER-encoded `SubjectPublicKeyInfo`. Each entry's
`input.spkiDerHex` is the exact SPKI DER bytes; positive entries' `expected.fingerprintHex` is
`sha256(spkiDer)`. At least 5 positive vectors use real, deterministically-derived P-256 keys
(`tools/vectors/spki_fingerprint.py` implements minimal P-256 scalar multiplication and ASN.1 DER
encoding directly against the standard library, so no third-party crypto dependency is needed) and
are cross-checked in the pytest suite against an independent `openssl pkey -pubin -outform DER |
openssl dgst -sha256` pipeline. Negative vectors cover a compressed SEC1 point
(`unsupportedPointEncoding`), a P-384 (secp384r1) key and an RSA-2048 key (both
`unsupportedKeyType`), and DER truncated by one byte (`malformedSpki`) — each MUST be rejected
before any fingerprint compare ever runs (SPEC.md, Certificate handling and the leaf-only check).

### `pairing-proof.json` (E01-18)

Vectors for SPEC.md `#2`'s pairing-proof HMAC (`proof = HMAC-SHA256(secret, ASCII("tandem-pair-v1")
|| LP(macSpkiDer) || LP(phoneSpkiDer) || LP(cb))`) and confirmation code (`ASCII("tandem-pair-code-v1")`
label, first 4 bytes of the HMAC-SHA256 output as `u32be` mod 1000000, zero-padded to 6 digits),
where `LP(x) = u16be(len(x)) || x`. Each entry's `input.kind` is `"proof"` or `"code"`.

`proof`-kind entries model the verifier side of the check: `input.secretHex`/`macSpkiDerHex`/
`phoneSpkiDerHex`/`cbHex` are the verifier's own session state and `input.proofHex` is the
candidate value under test. Positive entries' `expected` is `{"valid": true}`; negative entries use
`expectedError: "proofMismatch"` (proof computed with a different phone key, a different secret,
swapped `macSpkiDer`/`phoneSpkiDer` order, the `"tandem-pair-v1"` label omitted, no `LP` length
prefixes at all, or a different session's `cb` replayed against this one), `"malformedProof"` (a
31-byte proof where exactly 32 bytes are required), or `"malformedSpki"` (a 65-byte raw SEC1 point
where the 91-byte `SubjectPublicKeyInfo` DER is required) — each with `closeCode:
"PAIRING_FAILED"` and `localReason` `"BAD_PROOF"` (mismatch) or `"MALFORMED"` (structurally
invalid), per SPEC.md's `PairRejected` wire-collapse table.

`code`-kind entries' `expected.code` is the resulting 6-digit string, including one whose value has
a leading zero and one showing a different `cb` yields a different code. One additional vector
(`pairing-code-forwarded-challenge-relay`) has an identical `secret` and `cb` to
`pairing-code-fixture-a` but a different `macSpkiDer`; its code MUST still differ, proving the
forwarded-challenge evil-QR/relay detection property rests on the SPKI pair rather than on `cb`
(`docs/planning/decisions.md` D-71). `tools/vectors/pairing_proof.py` reuses
`spki_fingerprint.py`'s real P-256 SPKI DER derivation (distinct fixture labels, no collision with
`spki-fingerprint.json`'s own fixtures) for `macSpkiDer`/`phoneSpkiDer`.

### `qr-payload.json` (E01-21)

Vectors for SPEC.md `#pairing`'s `pair-uri` ABNF grammar (`tandem://pair?v=1&fp=...&s=...&a=...
&p=...&n=...`). Each entry's `input.uri` is the exact string a QR scanner would decode; valid
entries' `expected` gives the parsed `version`/`fingerprintHex`/`secretHex`/`addresses`/`port`/
`nameHex` (percent-decoded bytes, hex-encoded); malformed entries carry `expectedError` — one of
`missingRequiredField`, `duplicatedField`, `invalidEncoding`, `invalidFingerprint`,
`invalidSecret`, `invalidPort`, `invalidAddress`, `tooManyAddresses`, `invalidName`,
`unsupportedVersion`, `invalidScheme`, `invalidHost` — plus `input.invalidField` naming the single
query field responsible, where applicable. `tools/vectors/qr_payload.py`'s `parse_pair_uri` is the
reference parser both platforms' decoders are validated against; it uses the standard library
`ipaddress` module for the `a` field's literal-address rules (rejecting hostnames, zone IDs,
unspecified/multicast/broadcast addresses) and `base64`/`urllib.parse` for `fp`/`s`/`n`.

### `display-strings.json` (E01-24)

Vectors for SPEC.md `#untrusted-peer-strings-display-sanitization`'s seven-step sanitization order,
one vector per `kind` (`name` 64 / `title` 256 / `body` 4096 Unicode scalar values). Each entry's
`input.rawUtf8Hex` is the raw, possibly-invalid UTF-8 bytes a peer supplied (hex, so an invalid
byte sequence is representable) and `input.kind` selects the cap and single-line-vs-multi-line
rules; `expected.sanitized` is the fully sanitized string. `tools/vectors/display_strings.py` is
the reference sanitizer; grapheme-cluster-boundary vectors (an emoji ZWJ sequence, a flag emoji's
regional-indicator pair) are covered by a minimal, self-contained subset of UAX #29 rather than a
third-party/ICU grapheme-segmentation dependency — per the E01-24 backlog note, this vector suite
is itself the cross-platform tie-breaker if a platform's own ICU/Swift segmentation disagrees.

### `clipboard-encoding.json` (E31-01)

Vectors for `docs/protocol/SPEC.md` `#clipboard-channel`'s `ClipboardText` message
(`protocol/proto/tandem/v1/clipboard.proto`). Unlike `notify-encoding.json`/`status-encoding.json`,
entries here are the raw serialized `ClipboardText` message bytes, not a full `Envelope` frame:
`text` can be exactly at (or one byte past) its own 1,048,576-byte cap, which — once `Envelope`/
frame overhead is added — would itself exceed the unrelated 1 MiB `Envelope` frame-length cap
`frame-encoding.json` already covers, making a full-frame "exactly 1 MiB text is accepted" vector
self-contradictory. A small vector's `input.clipboardTextHex` inlines the exact message bytes;
the two boundary vectors instead give an `input.textRecipe` (`fillByte`/`fillLength`, the same
"compact recipe" idea as `frame-encoding.json`'s 1-MiB `Envelope` vector, above) plus
`originTag`/`sensitive`/`contentHashHex` so a `ClipboardText` can be reconstructed byte-for-byte
without this manifest embedding a megabyte-scale string. `content_hash` is
`SHA-256(UTF-8(text))` (`tools/vectors/clipboard_encoding.py`'s `content_hash_for`). Valid entries'
`expected` gives the decoded fields (and, for a recipe-based entry, a `clipboardTextSha256` over
the reconstructed message bytes to verify reconstruction); the one-byte-over-cap entry uses
`expectedError: "clipboardTextTooLarge"` — this is a message-level validation rejection, not a
frame-level close, so it carries no `closeCode`/`localReason`.

### `files-encoding.json` (E40-01)

Vectors for `docs/protocol/SPEC.md` `#files-channel`'s message types
(`protocol/proto/tandem/v1/files.proto`): `FileOffer`, `FileAccept`, `FileReject`, `FileChunk`,
`FileResumeRequest`. Like `clipboard-encoding.json`, entries here are the raw serialized message
bytes for one message type at a time (`input.messageHex`), not a full `Envelope` frame — necessary
because `FileChunk.data`'s own 262,144-byte (256 KiB) cap (`#files-channel` "Chunking") is a
message-level, app-enforced limit that protobuf's `bytes` wire type does not itself impose, and
which would otherwise interact confusingly with the unrelated 1 MiB `Envelope` frame-length cap
`frame-encoding.json` already covers. `input.kind` selects which message type `messageHex` decodes
as (`fileOffer`/`fileAccept`/`fileReject`/`fileChunk`/`fileResumeRequest`); valid entries'
`expected` gives the decoded fields directly (`sha256Hex`/`dataHex` hex-encoded, `reason` as the
`TRANSFER_REASON_*` name). The manifest includes a `FileReject` for every one of the 12
`TransferReason` values (E01-22's `BUSY` and `TOO_LARGE` included). The one oversized-chunk entry
gives a `dataRecipe` (`fillByte`/`fillLength`, the same "compact recipe" idea as
`frame-encoding.json`'s 1-MiB `Envelope` vector, above) at 262,145 bytes — one byte past the cap —
and uses `expectedError: "fileChunkPayloadTooLarge"`, a message-level validation rejection rather
than a frame-level close, so it carries no `closeCode`/`localReason`.

### `photos-encoding.json` (E41-01)

Vectors for `docs/protocol/SPEC.md` `#files-channel`'s "Photos" subsection's message types
(`protocol/proto/tandem/v1/photos.proto`): `PhotoPageResult` (with its `PhotoMeta` entries),
`ThumbResult`, `OriginalRequest`, and `PhotoError`. Like `files-encoding.json`, entries here are
the raw serialized message bytes for one message type at a time (`input.messageHex`), not a full
`Envelope` frame. `input.kind` selects which message type `messageHex` decodes as
(`photoPageResult`/`thumbResult`/`originalRequest`/`photoError`); valid entries' `expected` gives
the decoded fields directly (`pngBytesHex` hex-encoded plus a `pngBytesSha256` for independent
verification, `access`/`kind`/`reason` as their enum name). The manifest includes a
`PhotoPageResult` with `access: PHOTO_ACCESS_PARTIAL`, a `ThumbResult` carrying a minimal valid PNG
fixture, an `OriginalRequest`, and a `PhotoError` for every one of the 4 `PhotoErrorReason` values
(E01-22's Cycle-4 `BUSY` included).

### `contacts-encoding.json` (E51-01)

Vectors for `docs/protocol/SPEC.md` `#contacts-channel`'s message types
(`protocol/proto/tandem/v1/contacts.proto`): `Contact` (with its nested `PhoneNumber`/`Email`),
`ContactsSyncRequest`, `ContactsSyncResponse`. Like `files-encoding.json`, entries here are the raw
serialized message bytes for one message type at a time (`input.messageHex`), not a full
`Envelope` frame; `input.kind` selects which message type `messageHex` decodes as
(`contact`/`contactsSyncRequest`/`contactsSyncResponse`). The manifest includes: a full `Contact`
record with two phone numbers, one email and a `photo_thumbnail`, round-tripping identically on
both codecs; a `ContactsSyncRequest`; a `ContactsSyncResponse` with three
`deleted_contact_ids` (tombstones) and zero `contacts`; and a `Contact` whose `photo_thumbnail` is
one byte past the 32,768-byte (32 KiB) cap (`#contacts-channel` "Thumbnail cap") -- given as a
`thumbnailRecipe` (`fillByte`/`fillLength`, the same "compact recipe" idea as
`frame-encoding.json`'s 1-MiB `Envelope` vector, above) -- using `expectedError:
"contactPhotoThumbnailTooLarge"`, a message-level validation rejection rather than a frame-level
close, so it carries no `closeCode`/`localReason`. This cap is expressed in bytes, not pixels: a
parser decoding `photo_thumbnail` cannot check the JPEG's decoded pixel dimensions, only its byte
length (`docs/planning/backlog/phase-5.yaml` E51-01 notes).

### `sms-encoding.json` (E50-01)

Vectors for `docs/protocol/SPEC.md` `#sms-channel`'s message types
(`protocol/proto/tandem/v1/sms.proto`): `SmsMessage`, `SendSmsStatus`, `SmsSyncResponse`. Entries
are the raw serialized message bytes for one message type at a time (`input.messageHex`);
`input.kind` selects the type (`smsMessage`/`sendSmsStatus`/`smsSyncResponse`). The manifest
includes a full `SmsMessage` (with a `messageSha256`), a `SendSmsStatus` for each of the four
`SendSmsState` values (`FAILED` carrying `TOO_LONG`), and an `SmsSyncResponse` with one thread, two
messages and a backfill cursor. The `smsEnvelopeFrame` vector gives only the 4-byte length prefix
of a frame one byte over the 1 MiB maximum (`input.frameHex`) and is run through each platform's
real frame decoder: `expectedError: "malformedFrame"` with `closeCode`/`localReason`
(`MALFORMED_FRAME`/`TOO_LARGE`), rejected before any payload buffer is allocated.

### `calls-encoding.json` (E52-01)

Vectors for `docs/protocol/SPEC.md` `#calls-channel`'s message types
(`protocol/proto/tandem/v1/calls.proto`): `CallEvent`, `CallActionResult`. Entries are the raw
serialized message bytes (`input.messageHex`); `input.kind` selects the type
(`callEvent`/`callActionResult`). The `callStateSequence` kind carries an ordered list of `CallEvent`
bodies for one call (`input.messageHexes`). The manifest includes an incoming `RINGING` `CallEvent`
(with a `messageSha256`; both codecs also re-encode it to the same bytes), the
`RINGING`/`ACTIVE`/`ENDED` sequence of one call, and failed `CallActionResult`s for `UNKNOWN_CALL`,
`INVALID_NUMBER` and `RATE_LIMITED`.

## Authoritativeness

Per E01-16, a vector category is not authoritative until its PR is reviewed and approved: both
platform teams must be able to reproduce the same expected outputs independently before any
downstream issue that consumes a category (E01-17..E01-21) is marked done.

### `filenames.json` (E40-02)

Vectors for SPEC.md `#filename-sanitization`. `input.rawUtf8Hex` is the UTF-8 of
`FileOffer.name` (hex, so NUL, bidi controls and NFD text survive editors) and
`input.transferId` is `FileOffer.id`. Valid entries give `expected.filename`; a name containing
U+0000 uses `expectedError: "invalidName"` (the receiver answers `FileReject{INVALID_NAME}`).
