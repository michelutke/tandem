#!/usr/bin/env bash
# E00-17 tdd:
#   ci: releaseLogLint_clipboardTextInReleaseSourceSet_detektFails
#   ci: releaseLogLint_clipboardTextInDebugSourceSet_detektPasses
#
# Rule-logic coverage (redaction, shared-list wiring) lives in the detekt `lint()` unit tests at
# android/lint/detekt-rules/src/test/kotlin/dev/tandem/lint/detekt/NoSensitiveReleaseLogTest.kt;
# this script exercises the part unit tests cannot reach: the `excludes` glob in detekt.yml that
# scopes the rule to release-visible source sets, against a real Gradle/detekt run.
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
MAIN_FIXTURE="$ANDROID/core/crypto/src/main/kotlin/dev/tandem/core/crypto/NoSensitiveReleaseLogFixture.kt"
DEBUG_FIXTURE="$ANDROID/core/crypto/src/debug/kotlin/dev/tandem/core/crypto/NoSensitiveReleaseLogFixture.kt"
cleanup() {
  rm -f "$MAIN_FIXTURE" "$DEBUG_FIXTURE"
  rmdir -p "$(dirname "$MAIN_FIXTURE")" 2>/dev/null || true
  rmdir -p "$(dirname "$DEBUG_FIXTURE")" 2>/dev/null || true
}
trap cleanup EXIT
cd "$ANDROID"

fixture_body() {
  cat <<'KT'
package dev.tandem.core.crypto

import android.util.Log

internal fun logClipboard(clipboardText: String) {
    Log.d("clip", clipboardText)
}
KT
}

mkdir -p "$(dirname "$MAIN_FIXTURE")"
fixture_body > "$MAIN_FIXTURE"
if out="$(./gradlew -q :core:crypto:detekt 2>&1)"; then
  echo "FAIL releaseLogLint_clipboardTextInReleaseSourceSet_detektFails: detekt passed" >&2
  echo "$out" >&2
  exit 1
fi
grep -q "NoSensitiveReleaseLog" <<<"$out" || {
  echo "FAIL: detekt failed without NoSensitiveReleaseLog" >&2
  echo "$out" >&2
  exit 1
}
echo "OK releaseLogLint_clipboardTextInReleaseSourceSet_detektFails"
rm -f "$MAIN_FIXTURE"

mkdir -p "$(dirname "$DEBUG_FIXTURE")"
fixture_body > "$DEBUG_FIXTURE"
if ! out="$(./gradlew -q :core:crypto:detekt 2>&1)"; then
  echo "FAIL releaseLogLint_clipboardTextInDebugSourceSet_detektPasses: detekt failed" >&2
  echo "$out" >&2
  exit 1
fi
echo "OK releaseLogLint_clipboardTextInDebugSourceSet_detektPasses"
