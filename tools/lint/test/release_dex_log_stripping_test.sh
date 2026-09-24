#!/usr/bin/env bash
# E00-17 tdd:
#   ci: releaseDex_logVerboseDebugInfoCallSites_strippedByR8
#
# Builds :app:assembleRelease with R8 on and verifies android/app/proguard-rules.pro's
# `-assumenosideeffects` rule strips android.util.Log.v/d/i call sites from the release dex
# while leaving Log.w/Log.e in place. The app ships no code yet, so this plants a tiny,
# temporary fixture (never shipped) purely to give R8 a Log call site to strip.
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
FIXTURE="$ANDROID/app/src/main/kotlin/dev/tandem/app/LogStrippingFixture.kt"
PROGUARD_RULES="$ANDROID/app/proguard-rules.pro"
WORKDIR="$(mktemp -d)"

cleanup() {
  rm -f "$FIXTURE"
  rmdir -p "$(dirname "$FIXTURE")" 2>/dev/null || true
  [ -f "$WORKDIR/proguard-rules.pro.orig" ] && cp "$WORKDIR/proguard-rules.pro.orig" "$PROGUARD_RULES"
  rm -rf "$WORKDIR"
}
trap cleanup EXIT
cd "$ANDROID"
cp "$PROGUARD_RULES" "$WORKDIR/proguard-rules.pro.orig"

sdk_dir() {
  if [ -n "${ANDROID_HOME:-}" ]; then
    echo "$ANDROID_HOME"
  elif [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    echo "$ANDROID_SDK_ROOT"
  else
    sed -n 's/^sdk.dir=//p' local.properties
  fi
}
DEXDUMP="$(sdk_dir)/build-tools/36.0.0/dexdump"
[ -x "$DEXDUMP" ] || { echo "FAIL: dexdump not found at $DEXDUMP (need build-tools;36.0.0)" >&2; exit 1; }

mkdir -p "$(dirname "$FIXTURE")"
cat > "$FIXTURE" <<'KT'
package dev.tandem.app

import android.util.Log

fun logStrippingFixture(message: String) {
    Log.v("fixture", message)
    Log.d("fixture", message)
    Log.i("fixture", message)
    Log.w("fixture", message)
    Log.e("fixture", message)
}
KT
# R8 would otherwise tree-shake this unreferenced fixture entirely (the skeleton app has no
# other entry points yet); keep it reachable so only the Log v/d/i rule is under test.
echo '-keep class dev.tandem.app.LogStrippingFixtureKt { *; }' >> "$PROGUARD_RULES"

./gradlew -q :app:assembleRelease

APK="$ANDROID/app/build/outputs/apk/release/app-release-unsigned.apk"
[ -f "$APK" ] || { echo "FAIL: $APK not built" >&2; exit 1; }
unzip -q -o "$APK" classes.dex -d "$WORKDIR"
"$DEXDUMP" -d "$WORKDIR/classes.dex" > "$WORKDIR/dump.txt"

for stripped in v d i; do
  if grep -q "Landroid/util/Log;\.$stripped:" "$WORKDIR/dump.txt"; then
    echo "FAIL releaseDex_logVerboseDebugInfoCallSites_strippedByR8: Log.$stripped call site survived R8" >&2
    exit 1
  fi
done
for kept in w e; do
  grep -q "Landroid/util/Log;\.$kept:" "$WORKDIR/dump.txt" || {
    echo "FAIL releaseDex_logVerboseDebugInfoCallSites_strippedByR8: Log.$kept call site missing (fixture over-stripped)" >&2
    exit 1
  }
done
echo "OK releaseDex_logVerboseDebugInfoCallSites_strippedByR8"
