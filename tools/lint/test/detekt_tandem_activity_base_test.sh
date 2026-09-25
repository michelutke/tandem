#!/usr/bin/env bash
# E00-28 tdd:
#   ci: activityBaseClassLint_activityNotExtendingTandemActivity_lintFails
#
# Rule-logic coverage lives in the detekt `lint()` unit tests at
# android/lint/detekt-rules/src/test/kotlin/dev/tandem/lint/detekt/TandemActivityBaseTest.kt; this
# script exercises the part unit tests cannot reach: a real `:app:detekt` Gradle run.
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
FIXTURE="$ANDROID/app/src/main/kotlin/dev/tandem/app/TandemActivityBaseFixture.kt"
trap 'rm -f "$FIXTURE"' EXIT
cd "$ANDROID"

cat > "$FIXTURE" <<'KT'
package dev.tandem.app

import android.app.Activity

internal class RogueActivityFixture : Activity()
KT
if out="$(./gradlew -q :app:detekt 2>&1)"; then
  echo "FAIL activityBaseClassLint_activityNotExtendingTandemActivity_lintFails: detekt passed" >&2
  exit 1
fi
grep -q "TandemActivityBase" <<<"$out" || {
  echo "FAIL: detekt failed without TandemActivityBase" >&2
  echo "$out" >&2
  exit 1
}
echo "OK activityBaseClassLint_activityNotExtendingTandemActivity_lintFails"
