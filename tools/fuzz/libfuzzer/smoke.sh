#!/usr/bin/env bash
# E15-14: CI/local smoke entrypoint for the libFuzzer target over TandemProtocol's FrameDecoder.
#
# Runs on every PR touching macos/Packages/TandemProtocol/** or tools/fuzz/libfuzzer/**
# (.github/workflows/macos-fuzz.yml), 10 min job wall-clock budget:
#
#   1. `swift test` for FrameEnvelopeFuzzerCore — the seed corpus (protocol/vectors/
#      frame-encoding.json, via generate_seed_corpus.py) replayed through `fuzzOne` on a plain
#      Swift toolchain, no sanitizer required. Always runs; always must pass.
#   2. build_fuzz_target.sh — builds the real `-sanitize=fuzzer,address` binary. Apple's Xcode
#      toolchain cannot do this (no libFuzzer runtime); the Swift.org / Linux `swift:*` Docker
#      toolchain can. If the build fails, this step is skipped with a clear message rather than
#      failing the job — step 1 already gates the PR on this toolchain.
#   3. If the real target built, run_fuzz_target.sh replays the seed corpus and every reproducer in
#      tools/fuzz/regression/frame through it (0 crashes
#      required) and then fuzzes for up to 300s (a timeout alone is not a failure).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo "=== generating seed corpus from protocol/vectors/frame-encoding.json ==="
if ! python3 "$DIR/generate_seed_corpus.py" "$WORK/corpus"; then
  echo "smoke.sh: seed corpus generation failed" >&2
  exit 1
fi

echo "=== staging regression reproducers (tools/fuzz/regression/frame) ==="
"$DIR/../regression/stage.sh" "$WORK/corpus" frame || exit 1

echo "=== swift test: FrameEnvelopeFuzzerCore (cross-platform, no sanitizer) ==="
if ! (cd "$DIR/swift" && swift test); then
  echo "smoke.sh: swift test failed" >&2
  exit 1
fi

echo "=== attempting to build the real libFuzzer target ==="
if ! "$DIR/build_fuzz_target.sh" "$WORK/fuzz-target"; then
  echo "smoke.sh: real libFuzzer target unavailable on this toolchain, skipping the ASan run" \
       "(the swift test run above already gates this PR — see README.md)"
  exit 0
fi

echo "=== running the real target (seed replay + 300s budgeted fuzz) ==="
"$DIR/run_fuzz_target.sh" "$WORK/fuzz-target" "$WORK/corpus" "$WORK/artifacts" 300
status=$?
if [ "$status" -ne 0 ]; then
  mkdir -p "$DIR/artifacts"
  cp "$WORK"/artifacts/crash-* "$DIR/artifacts/" 2>/dev/null || true
  echo "smoke.sh: real target found a crash; reproducer(s) copied to tools/fuzz/libfuzzer/artifacts/" >&2
fi
exit "$status"
