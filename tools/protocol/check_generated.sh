#!/usr/bin/env bash
# E00-10: regenerate all protocol code and fail if the working tree differs, so hand-edits of
# generated *.pb.kt / *.pb.swift / *.java files (and forgotten regenerations) never land.
#
#   tools/protocol/check_generated.sh [repo-root]
set -euo pipefail
REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
OUT_DIRS=(android/core/protocol/src/main macos/Packages/TandemProtocol/Sources/TandemProtocol)

"$REPO_ROOT/tools/protocol/generate.sh"
cd "$REPO_ROOT"
changed="$(git status --porcelain -- "${OUT_DIRS[@]}")"
if [[ -n "$changed" ]]; then
  echo "Generated protocol code differs from protocol/proto. Never hand-edit generated files:" >&2
  echo "change the .proto and run tools/protocol/generate.sh, then commit the result." >&2
  echo "$changed" >&2
  git --no-pager diff -- "${OUT_DIRS[@]}" >&2
  exit 1
fi
echo "generated protocol code check: OK"
