#!/usr/bin/env bash
# E00-30 tdd:
#   ci: releaseApkDexScan_testOnlyClassFixture_exitsNonZero
#   ci: releaseApkDexScan_currentReleaseBuild_noTestOnlyClasses
#   ci: releaseApk_companionAppPackage_absentFromDexAndManifest
#
# Builds :app:assembleRelease and runs tools/release-audit/scan-test-code.rb over the dexdump'd
# release APK and merged manifest. Verifies the current (test-code-free) release build passes,
# then plants a temporary SoftwareIdentityKeyStore fixture class (kept reachable through R8 via a
# -keep rule, mirroring release_dex_log_stripping_test.sh) and verifies the scan fails naming it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID="$ROOT/android"
SCANNER="$ROOT/tools/release-audit/scan-test-code.rb"
FIXTURE="$ANDROID/app/src/main/kotlin/dev/tandem/app/SoftwareIdentityKeyStoreFixture.kt"
PROGUARD_RULES="$ANDROID/app/proguard-rules.pro"
APK="$ANDROID/app/build/outputs/apk/release/app-release-unsigned.apk"
MANIFEST="$ANDROID/app/build/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml"
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

dump_dex() {
  local out="$1"
  : > "$out"
  local dex_count
  dex_count="$(unzip -l "$APK" 'classes*.dex' 2>/dev/null | grep -c '\.dex$' || true)"
  if [ "$dex_count" -gt 0 ]; then
    unzip -q -o "$APK" 'classes*.dex' -d "$WORKDIR/dex"
    for dex in "$WORKDIR"/dex/classes*.dex; do
      "$DEXDUMP" -d "$dex" >> "$out"
    done
  fi
}

# --- current release build: no test-only classes, no companion package ---
./gradlew -q :app:assembleRelease
[ -f "$APK" ] || { echo "FAIL: $APK not built" >&2; exit 1; }

dump_dex "$WORKDIR/clean-dump.txt"
if ! ruby "$SCANNER" text "$WORKDIR/clean-dump.txt" > "$WORKDIR/clean-out.txt" 2>&1; then
  echo "FAIL releaseApkDexScan_currentReleaseBuild_noTestOnlyClasses: scan failed on current build" >&2
  cat "$WORKDIR/clean-out.txt" >&2
  exit 1
fi
echo "OK releaseApkDexScan_currentReleaseBuild_noTestOnlyClasses"

[ -f "$MANIFEST" ] || { echo "FAIL: merged manifest not found at $MANIFEST" >&2; exit 1; }
if ! ruby "$SCANNER" text "$WORKDIR/clean-dump.txt" "$MANIFEST" > "$WORKDIR/companion-out.txt" 2>&1; then
  echo "FAIL releaseApk_companionAppPackage_absentFromDexAndManifest: scan failed on current build" >&2
  cat "$WORKDIR/companion-out.txt" >&2
  exit 1
fi
echo "OK releaseApk_companionAppPackage_absentFromDexAndManifest"

# --- fixture: a planted SoftwareIdentityKeyStore class must be caught by name ---
mkdir -p "$(dirname "$FIXTURE")"
cat > "$FIXTURE" <<'KT'
package dev.tandem.app

// Never shipped: exists only to prove the release scan catches a fake keystore by name.
internal class SoftwareIdentityKeyStore
KT
echo '-keep class dev.tandem.app.SoftwareIdentityKeyStore { *; }' >> "$PROGUARD_RULES"

./gradlew -q :app:assembleRelease
dump_dex "$WORKDIR/fixture-dump.txt"
if out="$(ruby "$SCANNER" text "$WORKDIR/fixture-dump.txt" 2>&1)"; then
  echo "FAIL releaseApkDexScan_testOnlyClassFixture_exitsNonZero: scan passed with fixture present" >&2
  exit 1
fi
grep -q "SoftwareIdentityKeyStore" <<<"$out" || { echo "FAIL: scan failed without naming SoftwareIdentityKeyStore" >&2; echo "$out" >&2; exit 1; }
echo "OK releaseApkDexScan_testOnlyClassFixture_exitsNonZero"
