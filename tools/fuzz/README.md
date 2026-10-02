tools/fuzz — E15-13, E15-14: Jazzer (Kotlin) and libFuzzer (Swift) frame/envelope parser fuzz targets.

- `libfuzzer/` — E15-14: the Swift/libFuzzer target and its CI smoke run (see its own README.md).
- `jazzer/` — E15-13: the Kotlin/Jazzer CI wrapper (layout below).
- `campaign/` — E71-01: 24 h campaign runner (see below).

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

## E71-01 (24 h campaign)

`campaign/run_campaign.sh <jazzer|libfuzzer> <total-seconds> <segment-seconds> <state-dir>` fuzzes
in chunks and resumes from `<state-dir>` (corpus + `state.env` counters), so a campaign longer than
a 6 h runner job runs as several segments. It writes `<state-dir>/campaign-log.json` (duration,
total execs, final corpus size, crash count; E71-12 evidence) and exits 1 on a crash or hang
(libFuzzer runs use `-timeout=10`), leaving the reproducer in `<state-dir>/artifacts`. Self-test:
`campaign/test/run_campaign_test.sh`.

`.github/workflows/fuzz-campaign.yml` (manual `workflow_dispatch`, `total-seconds` default 86400)
runs both engines as 5 sequential segments of 17 400 s with the state in the Actions cache.
The libFuzzer engine needs `FUZZ_TARGET` (built by `libfuzzer/build_fuzz_target.sh`). Jazzer's
JUnit mode does not report an exec count, so `total_execs` stays 0 for Jazzer and its per-input
hang limit is Jazzer's own default timeout.

Local short run: `tools/fuzz/campaign/run_campaign.sh jazzer 60 60 "$TMPDIR/jz-campaign"`.
A crash reproducer becomes a regression test: add the bytes as a seed vector in
`protocol/vectors/frame-encoding.json`.
