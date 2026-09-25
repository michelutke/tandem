#!/usr/bin/env bash
# E15-13 tdd:
#   unit: jazzerSmokeWrapper_plantedCrashingTarget_exitsNonZeroWithReproducer
#   unit: jazzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero
#
# Runs one Jazzer JUnit @FuzzTest class (in android/core/protocol) in fuzzing mode
# (JAZZER_FUZZ=1) for a bounded duration and maps the outcome to an exit code:
#
#   0  no crash found — either the run exhausted its duration budget without one (timeout alone
#      is not a failure), or the seed-corpus/regression pass itself never fails.
#   1  Jazzer found a crash. The crashing input it saved to the fuzz test's "inputs directory"
#      (github.com/CodeIntelligenceTesting/jazzer README "Inputs directory") is copied to
#      <artifact-dir>/crash-input, and removed from the source tree so the crash doesn't linger
#      as an accidental permanent regression fixture.
#   2  usage or setup error (bad arguments, gradle invocation itself failed to even start).
#
# See tools/fuzz/jazzer/README.md for the full CLI contract.
set -euo pipefail

usage() {
  echo "usage: smoke.sh <fully-qualified-fuzz-test-class> <duration-seconds> <artifact-dir>" >&2
}

if [ "$#" -ne 3 ]; then
  usage
  exit 2
fi

CLASS_FQCN="$1"
DURATION_SECONDS="$2"
ARTIFACT_DIR="$3"

case "$DURATION_SECONDS" in
  '' | *[!0-9]*)
    echo "smoke.sh: duration-seconds must be a positive integer, got '$DURATION_SECONDS'" >&2
    exit 2
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID_DIR="$REPO_ROOT/android"
MODULE_DIR="$ANDROID_DIR/core/protocol"
GRADLEW="$ANDROID_DIR/gradlew"

if [ ! -x "$GRADLEW" ]; then
  echo "smoke.sh: $GRADLEW not found or not executable" >&2
  exit 2
fi

PKG_PATH="$(echo "${CLASS_FQCN%.*}" | tr '.' '/')"
CLASS_NAME="${CLASS_FQCN##*.}"
INPUTS_DIR="$MODULE_DIR/src/test/resources/$PKG_PATH/${CLASS_NAME}Inputs"

mkdir -p "$ARTIFACT_DIR"

MARKER="$(mktemp)"
cleanup() { rm -f "$MARKER"; }
trap cleanup EXIT

STATUS=0
JAZZER_FUZZ=1 JAZZER_MAX_DURATION="${DURATION_SECONDS}s" \
  "$GRADLEW" -p "$ANDROID_DIR" ":core:protocol:testDebugUnitTest" --tests "$CLASS_FQCN" --rerun --console=plain \
  || STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  echo "smoke.sh: no crash found ($CLASS_FQCN, budget ${DURATION_SECONDS}s)"
  exit 0
fi

CRASH_FILE=""
if [ -d "$INPUTS_DIR" ]; then
  CRASH_FILE="$(find "$INPUTS_DIR" -type f -newer "$MARKER" ! -name '.gitignore' 2>/dev/null | sort | tail -n 1)"
fi

if [ -z "$CRASH_FILE" ]; then
  echo "smoke.sh: gradle test failed for $CLASS_FQCN but no reproducer input was found in $INPUTS_DIR" >&2
  exit "$STATUS"
fi

cp "$CRASH_FILE" "$ARTIFACT_DIR/crash-input"
find "$INPUTS_DIR" -type f -newer "$MARKER" ! -name '.gitignore' -delete
echo "smoke.sh: crash found for $CLASS_FQCN; reproducer saved to $ARTIFACT_DIR/crash-input" >&2
exit 1
