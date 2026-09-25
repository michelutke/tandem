#!/usr/bin/env bash
# E00-28 tdd:
#   ci: pendingIntentLint_mutableWithoutAllowlistFixture_lintFails
#   ci: pendingIntentLint_implicitIntentFixture_lintFails
#
# Rule-logic coverage lives in the detekt `lint()` unit tests at
# android/lint/detekt-rules/src/test/kotlin/dev/tandem/lint/detekt/PendingIntentImmutableTest.kt;
# this script exercises the part unit tests cannot reach: a real `:app:detekt` Gradle run wired to
# the actual tools/lint/pending-intent-mutable.allowlist file.
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
FIXTURE="$ANDROID/app/src/main/kotlin/dev/tandem/app/PendingIntentImmutableFixture.kt"
trap 'rm -f "$FIXTURE"' EXIT
cd "$ANDROID"

cat > "$FIXTURE" <<'KT'
package dev.tandem.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

internal fun buildMutablePendingIntent(context: Context): PendingIntent =
    PendingIntent.getActivity(
        context,
        0,
        Intent(context, TandemActivity::class.java),
        PendingIntent.FLAG_MUTABLE,
    )
KT
if out="$(./gradlew -q :app:detekt 2>&1)"; then
  echo "FAIL pendingIntentLint_mutableWithoutAllowlistFixture_lintFails: detekt passed" >&2
  exit 1
fi
grep -q "PendingIntentImmutable" <<<"$out" || {
  echo "FAIL: detekt failed without PendingIntentImmutable" >&2
  echo "$out" >&2
  exit 1
}
echo "OK pendingIntentLint_mutableWithoutAllowlistFixture_lintFails"
rm -f "$FIXTURE"

cat > "$FIXTURE" <<'KT'
package dev.tandem.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

internal fun buildImplicitIntentPendingIntent(context: Context): PendingIntent =
    PendingIntent.getBroadcast(
        context,
        0,
        Intent("dev.tandem.app.ACTION_FOO"),
        PendingIntent.FLAG_IMMUTABLE,
    )
KT
if out="$(./gradlew -q :app:detekt 2>&1)"; then
  echo "FAIL pendingIntentLint_implicitIntentFixture_lintFails: detekt passed" >&2
  exit 1
fi
grep -q "PendingIntentImmutable" <<<"$out" || {
  echo "FAIL: detekt failed without PendingIntentImmutable" >&2
  echo "$out" >&2
  exit 1
}
echo "OK pendingIntentLint_implicitIntentFixture_lintFails"
