tools/fuzz/libfuzzer — E15-14: libFuzzer target for TandemProtocol's frame/envelope parser
(`FrameDecoder`), plus its CI smoke run. macOS counterpart to the Android Jazzer scaffolding
(E15-13, `tools/fuzz/jazzer/`).

## Layout

- `swift/` — a standalone SwiftPM package, `FrameEnvelopeFuzzerCore`, depending on
  `macos/Packages/TandemProtocol` by local path. It is a plain library: `swift build`/`swift test`
  never need a sanitizer, so it builds on any Swift 6.1+ toolchain (this repo's Xcode toolchain
  included). `Sources/FrameEnvelopeFuzzerCore/FuzzOne.swift` exposes the one function every
  harness below shares — `public func fuzzOne(_ data: Data)` — which runs one
  `FrameDecoder.decode(from:)` call over `data` via a fixed in-memory `FrameSource`.
  `Tests/FrameEnvelopeFuzzerCoreTests/SeedCorpusReplayTests.swift` replays every vector in
  `protocol/vectors/frame-encoding.json` (E01-19) through `fuzzOne` on every `swift test` run —
  this is the part of "replaying the full seed corpus produces 0 crashes" that needs no special
  toolchain.
- `swift/fuzzer-entry/LLVMFuzzerEntry.swift` — the libFuzzer C entry point
  (`@_cdecl("LLVMFuzzerTestOneInput")`), calling `fuzzOne`. Deliberately **outside**
  `swift/Sources/`, so no ordinary `swift build`/`swift test` ever compiles it. A libFuzzer target
  must not define its own Swift `main` (libFuzzer's own runtime supplies `main()`), and SwiftPM's
  executable-target validation requires exactly one `main.swift`/`@main` — there is no way to
  satisfy both inside one SwiftPM executable target. `build_fuzz_target.sh` instead builds
  `FrameEnvelopeFuzzerCore` as a static library via `swift build`, then links this one file
  against it with a direct `swiftc -sanitize=fuzzer,address -parse-as-library` invocation.
- `build_fuzz_target.sh <output-path>` — builds the real sanitizer binary (see above). **Fails on
  Apple's Xcode toolchain**: it does not ship the libFuzzer runtime, so `-sanitize=fuzzer` is
  rejected outright (confirmed locally: `error: unsupported option '-sanitize=fuzzer' for target
  'arm64-apple-macosx26.0'` on Swift 6.3.3 / Xcode). The open-source Swift.org toolchain and the
  official `swift` Docker images do ship it. `smoke.sh` treats a failed build as "skip the
  sanitizer run," not a hard failure — see below.
- `run_fuzz_target.sh <target-exe> <corpus-dir> <artifact-dir> <budget-seconds>` — generic runner
  for any libFuzzer-CLI-compatible executable: seed corpus replay (`-runs=0`, 0 crashes required),
  then budgeted fuzzing (`-max_total_time=<budget>`; exhausting the budget without a crash is
  success, not a timeout failure). Used both by `smoke.sh` (the real target) and by
  `test/run_fuzz_target_test.sh` (a fixture target), so the crash-detection/reproducer-saving
  logic is exercised without needing the real target.
- `fixtures/planted_crasher.py` — a fake libFuzzer-CLI target that deliberately "crashes" (exits 1,
  saves a `crash-<sha1>` reproducer file) the moment it reads an input starting with the magic
  prefix `CRASH`; inert otherwise. Proves crash detection independently of the real Swift parser.
- `test/run_fuzz_target_test.sh` — unit tests of `run_fuzz_target.sh` against the fixture:
  - `libFuzzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer`
  - `libFuzzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero`
- `generate_seed_corpus.py <output-dir>` — materializes `protocol/vectors/frame-encoding.json`
  (E01-19) as raw frame files (one per vector), reusing `tools/vectors/frame_encoding.py`'s
  `build_frame_from_vector` (the same reference builder every language's vector fixture uses) so
  the corpus never drifts from the checked-in manifest.
- `smoke.sh` — the CI/local entrypoint: generates the seed corpus, runs `swift test`
  (always, cross-platform), then attempts `build_fuzz_target.sh` + `run_fuzz_target.sh` with a
  300s budget; skips the latter with an explanatory message if the toolchain can't build it.

## Running locally

```sh
tools/fuzz/libfuzzer/smoke.sh
```

On the Xcode toolchain this runs the seed-corpus replay test and then reports that the real
sanitizer target could not be built, exiting 0. To get the real ASan/libFuzzer run, use a Swift.org
or Linux `swift` toolchain (see `.github/workflows/fuzz-libfuzzer.yml`).

## Wrapper self-test

```sh
tools/fuzz/libfuzzer/test/run_fuzz_target_test.sh
```

## Per-domain decoders (E71-13)

`build_fuzz_target.sh <output> domain` builds one generic libFuzzer binary
(`fuzzer-entry/LLVMFuzzerDomainEntry.swift`) for every Swift domain decoder; the proto file is picked
at run time with `TANDEM_FUZZ_MESSAGE=<stem>` (e.g. `media_control`). The registry is
`swift/Sources/FrameEnvelopeFuzzerCore/DomainFuzzRegistry.swift`: one entry per
`protocol/proto/tandem/v1/*.proto`, decoding the fuzz bytes as every top-level message of that file.
`media.proto` additionally drives `FragmentReassembler` (E61-14) with fragment sequences
(`pts, fragmentIndex, fragmentCount, length` headers followed by payload). The reassembler source is
symlinked into the package as `MirrorFragmentReassembler`, because `FeatureMirror` as a whole does not
build on Linux.

`check_registry.sh` exits non-zero naming any proto file without an entry; self-test
`test/check_registry_test.sh`. The 24 h campaigns run through `fuzz-campaign.yml` with `target=domain`
and `message=<stem>`, one dispatch per proto file.
