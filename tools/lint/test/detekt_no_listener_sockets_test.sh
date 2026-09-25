#!/usr/bin/env bash
# E12-04 tdd:
#   ci: noListenerLint_serverSocketInMainSourceFixture_fails
#   ci: noListenerLint_currentTree_passes
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
FIXTURE="$ANDROID/core/transport/src/main/kotlin/dev/tandem/core/transport/NoListenerSocketsFixture.kt"
trap 'rm -f "$FIXTURE"' EXIT
cd "$ANDROID"

cat > "$FIXTURE" <<'KT'
package dev.tandem.core.transport

import java.net.ServerSocket

internal fun listenFixture(port: Int): ServerSocket = ServerSocket(port)
KT
if out="$(./gradlew -q :core:transport:detekt 2>&1)"; then
  echo "FAIL noListenerLint_serverSocketInMainSourceFixture_fails: detekt passed" >&2
  exit 1
fi
grep -q "NoListenerSockets" <<<"$out" || { echo "FAIL: detekt failed without NoListenerSockets" >&2; echo "$out" >&2; exit 1; }
echo "OK noListenerLint_serverSocketInMainSourceFixture_fails"
rm -f "$FIXTURE"

if ! out="$(./gradlew -q :core:transport:detekt 2>&1)"; then
  echo "FAIL noListenerLint_currentTree_passes: detekt failed" >&2
  echo "$out" >&2
  exit 1
fi
echo "OK noListenerLint_currentTree_passes"
