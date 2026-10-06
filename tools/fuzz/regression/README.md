tools/fuzz/regression — E71-05: minimized reproducers of every crash or hang a fuzz run has found.

Layout: `regression/<target>/<short-description>.bin`, where `<target>` is `frame`, `envelope`, `qr`, or
the proto file stem of a domain decoder (`media`, `sms`, ...; create the directory with the first
reproducer). Files are permanent; see [docs/security/fuzzing.md](../../../docs/security/fuzzing.md) for
the triage process.

Replay: `stage.sh <dest-dir> <target>...` copies every reproducer of the given targets into `dest-dir`
as `regression-<target>-<name>`, and prints the count. Both smoke scripts call it and fail on any
reproducer that crashes or hangs:

- `jazzer/smoke.sh` stages into the fuzz test's inputs directory, which Jazzer replays before fuzzing
  (`frame`, `envelope`, `qr` by test class; domain tests by `TANDEM_FUZZ_MESSAGE`, else every domain dir).
- `libfuzzer/smoke.sh` stages into the corpus directory, which libFuzzer replays first (`frame`).

Self-test: `test/stage_test.sh`.
