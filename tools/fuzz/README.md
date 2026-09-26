tools/fuzz — E15-13, E15-14: Jazzer (Kotlin) and libFuzzer (Swift) frame/envelope parser fuzz targets.

- `libfuzzer/` — E15-14: the Swift/libFuzzer target and its CI smoke run (see its own README.md).
- `jazzer/` — E15-13: the Kotlin/Jazzer CI wrapper (layout below).

## E15-13 (Jazzer / Android) layout

The Jazzer fuzz *test classes* live under `android/core/protocol/src/test/kotlin/dev/tandem/core/protocol/fuzz/`
rather than a standalone project rooted at `tools/fuzz/jazzer/`: they wrap `FrameDecoder.decodeFrame`
and are seeded from `protocol/vectors/frame-encoding.json` by reusing `FrameVectorTestSupport`
(vector loading, `envelopeRecipe` reconstruction) already shared with `FrameEncoderTest`/
`FrameDecoderTest` — putting them in `core/protocol`'s own test source set means they compile
against the real module and that helper directly, instead of duplicating its logic in a second
project. `tools/fuzz/jazzer/` is the operational/CI-facing home:

- `tools/fuzz/jazzer/smoke.sh` — the CI/local wrapper; see `tools/fuzz/jazzer/README.md`.
- `tools/fuzz/jazzer/test/*.sh` — the wrapper's own self-tests (planted-crasher fixture, short
  budget-exhausted run).

See `tools/fuzz/jazzer/README.md` for the full contract.
