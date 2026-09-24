#!/usr/bin/env bash
# E00-09 checks:
#   ci: bufGenerate_placeholderMessage_kotlinAndSwiftOutputCompiles
#   ci: bufGenerate_runTwice_outputByteIdentical
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT_DIRS=(android/core/protocol/src/main macos/Packages/TandemProtocol/Sources/TandemProtocol)

digest() { (cd "$REPO_ROOT" && find "${OUT_DIRS[@]}" -type f -print0 | sort -z | xargs -0 shasum -a 256); }

"$REPO_ROOT/tools/protocol/generate.sh"
first="$(digest)"
"$REPO_ROOT/tools/protocol/generate.sh"
second="$(digest)"
if [[ "$first" != "$second" ]]; then
  echo "FAIL bufGenerate_runTwice_outputByteIdentical: output changed between runs" >&2
  diff <(echo "$first") <(echo "$second") >&2 || true
  exit 1
fi
echo "OK bufGenerate_runTwice_outputByteIdentical"

(cd "$REPO_ROOT/android" && ./gradlew -q :core:protocol:compileDebugKotlin)
(cd "$REPO_ROOT/macos/Packages/TandemProtocol" && swift build -q)
echo "OK bufGenerate_placeholderMessage_kotlinAndSwiftOutputCompiles"
