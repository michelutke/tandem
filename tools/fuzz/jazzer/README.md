# tools/fuzz/jazzer (E15-13)

Jazzer JUnit fuzz scaffolding for the Android frame/envelope parser
(`android/core/protocol`'s `FrameDecoder` + generated `Envelope`).

## Layout

- The fuzz test classes live in `android/core/protocol/src/test/kotlin/dev/tandem/core/protocol/fuzz/`,
  compiled and run as part of `:core:protocol`'s normal JUnit 5 test suite (`jazzer-junit` is a
  `testImplementation` dependency of that module — test-only, never on a release classpath):
  - `FrameDecoderFuzzTest` — the real target. Feeds fuzzer-mutated bytes through a one-shot
    `FrameSource` adapter into `FrameDecoder.decodeFrame`. Seeded from the E01-19 corpus
    (`protocol/vectors/frame-encoding.json`) via a JUnit `@MethodSource`, reusing
    `FrameVectorTestSupport`'s vector-loading/recipe-reconstruction helpers. Only an *uncaught
    exception* out of `decodeFrame` counts as a finding — `Frame`, `Rejected`, and `EndOfStream`
    are all legitimate outcomes already covered by `FrameDecoderTest`.
  - `fuzz/fixture/PlantedCrasherFuzzTest` — a deliberately broken fixture target (throws once its
    input starts with the magic ASCII prefix `JAZZER_CRASH_ME`), used only to self-test this
    directory's `smoke.sh`. Kept in its own `fixture` sub-package so it's never mistaken for
    production fuzzing.
- This directory (`tools/fuzz/jazzer/`) is the operational/CI-facing home:
  - `smoke.sh` — the wrapper described below.
  - `test/*.sh` — the wrapper's own self-tests.

- `android/core/pairing/src/test/kotlin/dev/tandem/core/pairing/fuzz/QrPayloadFuzzTest` (E71-03) — fuzzes
  `QrPayloadParser.parse` with UTF-8 bytes seeded from `protocol/vectors/qr-payload.json`. Run it with
  `JAZZER_MODULE=core:pairing tools/fuzz/jazzer/smoke.sh dev.tandem.core.pairing.fuzz.QrPayloadFuzzTest <s> <dir>`
  (`JAZZER_MODULE` selects the Gradle module, default `core:protocol`).

- `DomainDecoderFuzzTest` + `DomainFuzzRegistry` (E71-04) — one generic target over every domain message
  decoder in `:core:protocol`. `TANDEM_FUZZ_MESSAGE=<proto file stem>` (e.g. `media_control`) picks the
  proto file; unset, all entries run. The registry has one entry per `protocol/proto/tandem/v1/*.proto` and
  lists the `protocol/vectors` files that seed it. `check_registry.sh` exits non-zero naming any proto
  file without an entry (self-test `test/check_registry_test.sh`). `media.proto` fuzzes decoding only
  (`MediaFrame` etc.): the phone only sends fragments, so Android has no reassembly logic to drive. 24 h
  campaigns: `fuzz-campaign.yml` with `target=domain`, `message=<stem>`, one dispatch per proto file.

## Running fuzz tests normally

`./gradlew :core:protocol:test` (part of the existing `build` job's `./gradlew build`) runs both
`@FuzzTest` methods in **regression mode**: every seed argument (from `@MethodSource` for the real
target) is replayed once as an ordinary parameterized test case. This is how seed-corpus replay
against the real target — `ci: jazzerFrameTarget_seedCorpusReplay_zeroCrashes` — happens for free
on every PR, with no separate invocation needed.

## `smoke.sh`

```
tools/fuzz/jazzer/smoke.sh <fully-qualified-fuzz-test-class> <duration-seconds> <artifact-dir>
```

Runs the named `@FuzzTest` class in **fuzzing mode** (`JAZZER_FUZZ=1`, `JAZZER_MAX_DURATION=<duration-seconds>s`)
via `./gradlew :core:protocol:testDebugUnitTest --tests <class>` and maps the result to an exit code:

| Exit | Meaning |
|---|---|
| `0` | No crash found — either the duration budget was exhausted without one (a plain timeout is **not** a failure), or the run simply passed. |
| `1` | Jazzer found a crash. The crashing input (from Jazzer's ["inputs directory"](https://github.com/CodeIntelligenceTesting/jazzer/blob/main/README.md#inputs-directory), pre-created under each fuzz test class's `src/test/resources/.../<ClassName>Inputs/<method>/`) is copied to `<artifact-dir>/crash-input` and removed from the source tree (kept out of git — see the `.gitignore` in each `*Inputs/` directory — so a fixture/self-test crash never lingers as an accidental permanent regression file). |
| `2` | Usage or setup error (bad arguments, `gradlew` missing). |

Example — the CI smoke run against the real target (5 minutes fuzzing, `timeout-minutes: 10` on
the job itself per E15-13's acceptance criteria):

```sh
tools/fuzz/jazzer/smoke.sh dev.tandem.core.protocol.fuzz.FrameDecoderFuzzTest 300 /tmp/jazzer-artifacts
```

## Self-tests

`tools/fuzz/jazzer/test/*.sh` exercise `smoke.sh` itself, independently of the real parser:

- `jazzer_smoke_planted_crasher_test.sh` — runs `smoke.sh` against `PlantedCrasherFuzzTest` and
  asserts a non-zero exit plus a saved `crash-input` reproducer.
- `jazzer_smoke_budget_exhausted_test.sh` — runs `smoke.sh` against the real `FrameDecoderFuzzTest`
  with a short budget and asserts a zero exit with no reproducer.

These are wired into the `fuzz-smoke` CI job (`.github/workflows/android.yml`) ahead of the full
300s run against the real target.
