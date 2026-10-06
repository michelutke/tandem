# Fuzzing: campaigns and the fix-found-crashes process

Parser fuzzing for the frame decoder, the Envelope decoder, the QR pairing payload parser and every
per-domain message decoder (PRD security tests, AC-07). Tooling lives in
[`tools/fuzz`](../../tools/fuzz/README.md); this page defines what happens when a campaign finds
something (E71-05). The release checklist ([`release-audit.md`](release-audit.md)) cites the run logs
recorded here.

## Targets and budgets

| Target | Engines | Issue |
|---|---|---|
| Frame length-prefix parser | Jazzer, libFuzzer | E71-01 |
| Envelope protobuf decoder | Jazzer, libFuzzer | E71-02 |
| QR pairing payload parser | Jazzer (Android only; macOS never parses QR) | E71-03 |
| Per-domain message decoders, Kotlin | Jazzer | E71-04 |
| Per-domain message decoders, Swift | libFuzzer | E71-13 |

- PRs touching a parser run a short smoke run (E15-13, E15-14; 5 min per target, decision D-47).
- Before release every target runs a full campaign of at least 86 400 s wall clock with zero crashes,
  sanitizer findings or hangs. A single input running longer than 10 s is a hang.
- Campaigns run through `tools/fuzz/campaign/run_campaign.sh` and the manual
  `.github/workflows/fuzz-campaign.yml` workflow, which write `campaign-log.json` (duration, total
  execs, final corpus size, crash count).

## Triage process

Any crash, sanitizer finding or hang found by a campaign, a smoke run or a local run is handled as
follows. Nothing is waived, deferred or "known".

1. **Open a P0 bug.** File it in the owning feature epic's backlog YAML (`docs/planning/backlog/`),
   priority P0, `type: bug`, `tdd:` naming the regression test. Link the campaign run and attach the
   raw reproducer. Do not publish the reproducer outside the repository until the fix is merged.
2. **Minimize the reproducer.** Use the engine's minimizer (Jazzer `-minimize_crash=1`, libFuzzer
   `-minimize_crash=1`) until the input is the smallest that still fails. Record the crash class
   (exception type, sanitizer report, or timeout) in the bug.
3. **Add the permanent regression case.** Commit the minimized bytes under
   `tools/fuzz/regression/<target>/<short-description>.bin`, where `<target>` is the registry name
   (`frame`, `envelope`, `qr`, or the proto file name for a domain decoder). Files are never
   edited or removed; a case that no longer applies is replaced only by a recorded decision.
4. **Replay in CI.** The E15-13 and E15-14 smoke runs replay every file under
   `tools/fuzz/regression/` before fuzzing. A replay that crashes or hangs fails the run, naming the
   file (`ci: fuzzSmokeRun_regressionCorpusDir_replaysEveryReproducer`).
5. **Fix, test first.** Write the failing test from the reproducer, then fix the parser. Where the
   reproducer is a wire-format case, also add it as a seed vector under `protocol/vectors/` so both
   codecs agree on the rejection.
6. **Check the sibling codec.** The same input is run against the other implementation (Kotlin and
   Swift) and the other targets that share the decoder. A divergence is its own P0 bug.
7. **Re-run clean for 24 hours.** After the fix merges, the affected target runs a fresh campaign
   from its seed corpus plus the regression directory for at least 86 400 s with zero findings.
   Only that run closes the bug. Shorter or resumed-from-crashed-state runs do not count.
8. **Record the run.** Add a row to the table below and archive the `campaign-log.json` as release
   audit evidence.

A finding in a release candidate blocks the release audit until step 7 is recorded for the target.

## Clean-run record

One row per target and campaign. Each target needs at least one clean 24 h run recorded after this
process has been applied (E71-05 acceptance); the checklist rows reference these.

| Target | Engine | Date | Build SHA | Duration (s) | Total execs | Final corpus | Crashes | Log |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |
