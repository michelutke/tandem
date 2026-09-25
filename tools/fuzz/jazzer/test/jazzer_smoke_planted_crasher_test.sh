#!/usr/bin/env bash
# E15-13 tdd: unit: jazzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer
#
# Runs tools/fuzz/jazzer/smoke.sh against the planted-crasher fixture
# (PlantedCrasherFuzzTest#fuzzPlantedCrasher, which throws once its input starts with the
# "JAZZER_CRASH_ME" magic prefix) and checks that the wrapper exits non-zero and saves a
# reproducer input — proving the wrapper's own crash-detection/artifact-saving logic
# independently of the real FrameDecoder target.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SMOKE="$REPO_ROOT/tools/fuzz/jazzer/smoke.sh"
ARTIFACT_DIR="$(mktemp -d)"

cleanup() { rm -rf "$ARTIFACT_DIR"; }
trap cleanup EXIT

STATUS=0
"$SMOKE" "dev.tandem.core.protocol.fuzz.fixture.PlantedCrasherFuzzTest" 30 "$ARTIFACT_DIR" || STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  echo "FAIL jazzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer: exited 0 against a planted crasher" >&2
  exit 1
fi

if [ ! -s "$ARTIFACT_DIR/crash-input" ]; then
  echo "FAIL jazzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer: no reproducer artifact saved" >&2
  exit 1
fi

echo "OK jazzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer"
