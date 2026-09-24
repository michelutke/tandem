#!/usr/bin/env bash
# E00-18 tdd:
#   ci: injectedClockOnlyRule_currentTimeMillisInCoreModule_detektFails
# plus acceptance: core/testing never appears on the app's release runtime classpath.
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
FIXTURE="$ANDROID/core/crypto/src/main/kotlin/dev/tandem/core/crypto/InjectedClockOnlyFixture.kt"
trap 'rm -f "$FIXTURE"; rmdir -p "$(dirname "$FIXTURE")" 2>/dev/null || true' EXIT
cd "$ANDROID"

mkdir -p "$(dirname "$FIXTURE")"
cat > "$FIXTURE" <<'KT'
package dev.tandem.core.crypto

internal fun injectedClockOnlyFixture(): Long = System.currentTimeMillis()
KT
if out="$(./gradlew -q :core:crypto:detekt 2>&1)"; then
  echo "FAIL injectedClockOnlyRule_currentTimeMillisInCoreModule_detektFails: detekt passed" >&2
  exit 1
fi
grep -q "InjectedClockOnly" <<<"$out" || { echo "FAIL: detekt failed without InjectedClockOnly" >&2; echo "$out" >&2; exit 1; }
echo "OK injectedClockOnlyRule_currentTimeMillisInCoreModule_detektFails"

if ./gradlew -q :app:dependencies --configuration releaseRuntimeClasspath | grep -q ":core:testing"; then
  echo "FAIL: core/testing is on the app release runtime classpath" >&2
  exit 1
fi
echo "OK coreTesting_releaseRuntimeClasspath_absent"
