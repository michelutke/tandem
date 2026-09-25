#!/usr/bin/env bash
# E15-13 tdd: unit: jazzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero
#
# Runs tools/fuzz/jazzer/smoke.sh against the real FrameDecoderFuzzTest target for a short
# duration budget and checks that the wrapper exits 0 with no reproducer artifact once the
# budget is exhausted without a crash — timeout alone must not be treated as a failure.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SMOKE="$REPO_ROOT/tools/fuzz/jazzer/smoke.sh"
ARTIFACT_DIR="$(mktemp -d)"

cleanup() { rm -rf "$ARTIFACT_DIR"; }
trap cleanup EXIT

STATUS=0
"$SMOKE" "dev.tandem.core.protocol.fuzz.FrameDecoderFuzzTest" 8 "$ARTIFACT_DIR" || STATUS=$?

if [ "$STATUS" -ne 0 ]; then
  echo "FAIL jazzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero: exited $STATUS against the real FrameDecoder target" >&2
  exit 1
fi

if [ -e "$ARTIFACT_DIR/crash-input" ]; then
  echo "FAIL jazzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero: unexpected reproducer artifact" >&2
  exit 1
fi

echo "OK jazzerSmokeWrapper_budgetExhaustedWithoutCrash_exitsZero"
