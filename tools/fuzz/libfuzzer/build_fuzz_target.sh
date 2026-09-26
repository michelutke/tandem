#!/usr/bin/env bash
# E15-14: builds the real libFuzzer binary for TandemProtocol's FrameDecoder.
#
#   tools/fuzz/libfuzzer/build_fuzz_target.sh <output-path>
#
# `FrameEnvelopeFuzzerCore` (swift/) is a plain SwiftPM library: `swift build`/`swift test` never
# need `-sanitize=fuzzer`, so they work on any Swift 6.1+ toolchain. This script does the one part
# that does need it: it builds that library in debug config (so `@testable import TandemProtocol`
# inside it still resolves — SwiftPM only adds `-enable-testing` in debug), then links
# swift/fuzzer-entry/LLVMFuzzerEntry.swift against it with a direct `swiftc -sanitize=fuzzer,address`
# invocation (see that file for why it can't be an ordinary SwiftPM executable target).
#
# Apple's Xcode toolchain does not ship the libFuzzer runtime (only the open-source Swift.org
# toolchain and Linux swift:X.Y Docker images do), so this fails on a stock macOS dev machine —
# that is expected, not a bug. Exits non-zero with a message identifying the cause; callers
# (smoke.sh) treat that as "skip the real-target run" rather than a hard failure.
set -uo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: build_fuzz_target.sh <output-path>" >&2
  exit 2
fi
output="$1"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift_pkg="$dir/swift"

echo "== swift build (FrameEnvelopeFuzzerCore, debug, so @testable import stays enabled) =="
if ! (cd "$swift_pkg" && swift build --product FrameEnvelopeFuzzerCore); then
  echo "build_fuzz_target.sh: swift build failed" >&2
  exit 1
fi

bin_path="$(cd "$swift_pkg" && swift build --show-bin-path)"

echo "== swiftc -sanitize=fuzzer,address (linking the libFuzzer entry point) =="
if ! swiftc \
  -sanitize=fuzzer,address \
  -parse-as-library \
  -I "$bin_path/Modules" \
  -L "$bin_path" \
  -lFrameEnvelopeFuzzerCore \
  "$dir/swift/fuzzer-entry/LLVMFuzzerEntry.swift" \
  -o "$output" 2>&1; then
  echo "build_fuzz_target.sh: this Swift toolchain cannot link -sanitize=fuzzer (expected on the" \
       "Xcode toolchain; use the Swift.org toolchain or the swift Docker image instead — see README.md)" >&2
  exit 1
fi

echo "built $output"
