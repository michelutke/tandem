#!/usr/bin/env bash
# audit-step.sh (D-39 convention) for tools/fuzz — Kotlin (Jazzer, E15-13) and Swift (libFuzzer,
# E15-14) parser fuzz smoke runs. Invoked as: audit-step.sh --subset ci|full
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
subset="${2:-full}"

case "$subset" in
  ci) jazzer_seconds=60 ;;
  full) jazzer_seconds=300 ;;
  *)
    echo "ERROR: unknown subset ${subset}" >&2
    exit 1
    ;;
esac

artifacts="$(mktemp -d)"
trap 'rm -rf "$artifacts"' EXIT

"$here/jazzer/smoke.sh" dev.tandem.core.protocol.fuzz.FrameDecoderFuzzTest "$jazzer_seconds" "$artifacts"
"$here/libfuzzer/smoke.sh"
