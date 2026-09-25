#!/usr/bin/env bash
# E00-28 tdd (real-build wiring; fixture-only coverage for the same behaviors lives in the pure
# Ruby minitest suite at android_manifest_check_test.rb, run by repo-checks.yml):
#   ci: mergedManifest_allowBackupTrueFixture_checkFails
#   ci: exportedComponentCheck_unlistedExportedActivityFixture_checkFails
#
# Builds :app:assembleRelease and runs tools/release-audit/check-android-manifest.rb against the
# real merged release manifest and the real *packaged* release NSC / dataExtractionRules resources
# (build/intermediates/packaged_res/release/..., not src/main or src/release directly — a
# build-type-specific resource override only takes effect after resource merging, so reading the
# source file directly could miss it), verifying the current build passes; then proves the
# exported-component and allowBackup checks actually engage against that real build (not just
# fixtures).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ANDROID="$ROOT/android"
CHECKER="$ROOT/tools/release-audit/check-android-manifest.rb"
ALLOWLIST="$ROOT/tools/release-audit/android-exported.allowlist"
MANIFEST_SRC="$ANDROID/app/src/main/AndroidManifest.xml"
PACKAGED_RES="$ANDROID/app/build/intermediates/packaged_res/release/packageReleaseResources"
NSC="$PACKAGED_RES/xml/network_security_config.xml"
DATA_EXTRACTION_RULES="$PACKAGED_RES/xml/data_extraction_rules.xml"
MERGED_MANIFEST="$ANDROID/app/build/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml"
WORKDIR="$(mktemp -d)"

cleanup() {
  cp "$WORKDIR/AndroidManifest.xml.orig" "$MANIFEST_SRC"
  rm -rf "$WORKDIR"
}
trap cleanup EXIT
cd "$ANDROID"
cp "$MANIFEST_SRC" "$WORKDIR/AndroidManifest.xml.orig"

./gradlew -q :app:assembleRelease
[ -f "$MERGED_MANIFEST" ] || { echo "FAIL: merged manifest not found at $MERGED_MANIFEST" >&2; exit 1; }
[ -f "$NSC" ] || { echo "FAIL: packaged NSC resource not found at $NSC" >&2; exit 1; }
[ -f "$DATA_EXTRACTION_RULES" ] || { echo "FAIL: packaged dataExtractionRules resource not found at $DATA_EXTRACTION_RULES" >&2; exit 1; }

# --- current release build passes with the real allowlist ---
if ! out="$(ruby "$CHECKER" --manifest "$MERGED_MANIFEST" --nsc "$NSC" --data-extraction-rules "$DATA_EXTRACTION_RULES" --allowlist "$ALLOWLIST" 2>&1)"; then
  echo "FAIL androidManifestCheck_currentReleaseBuild_checkPasses: check failed on current build" >&2
  echo "$out" >&2
  exit 1
fi
echo "OK androidManifestCheck_currentReleaseBuild_checkPasses"

# --- exportedComponentCheck_unlistedExportedActivityFixture_checkFails: proven against the real
# merged manifest by removing the one real exported component from the allowlist. The only
# exported component in the current build is a library-injected androidx.profileinstaller
# receiver; if a future dependency bump drops it, this assertion has nothing to prove against and
# is skipped rather than failing spuriously. ---
if grep -q "ProfileInstallReceiver" "$MERGED_MANIFEST"; then
  EMPTY_ALLOWLIST="$WORKDIR/empty-allowlist"
  : > "$EMPTY_ALLOWLIST"
  if out="$(ruby "$CHECKER" --manifest "$MERGED_MANIFEST" --nsc "$NSC" --data-extraction-rules "$DATA_EXTRACTION_RULES" --allowlist "$EMPTY_ALLOWLIST" 2>&1)"; then
    echo "FAIL exportedComponentCheck_unlistedExportedActivityFixture_checkFails: check passed with empty allowlist" >&2
    exit 1
  fi
  grep -q "ProfileInstallReceiver" <<<"$out" || {
    echo "FAIL: check failed without naming the exported component" >&2
    echo "$out" >&2
    exit 1
  }
  echo "OK exportedComponentCheck_unlistedExportedActivityFixture_checkFails"
else
  echo "SKIP exportedComponentCheck_unlistedExportedActivityFixture_checkFails: ProfileInstallReceiver absent from the current build (no exported component to prove against)"
fi

# --- mergedManifest_allowBackupTrueFixture_checkFails: flip the real source manifest, rebuild ---
sed -i.bak 's/android:allowBackup="false"/android:allowBackup="true"/' "$MANIFEST_SRC"
rm -f "$MANIFEST_SRC.bak"
./gradlew -q :app:assembleRelease
if out="$(ruby "$CHECKER" --manifest "$MERGED_MANIFEST" --nsc "$NSC" --data-extraction-rules "$DATA_EXTRACTION_RULES" --allowlist "$ALLOWLIST" 2>&1)"; then
  echo "FAIL mergedManifest_allowBackupTrueFixture_checkFails: check passed with allowBackup=true" >&2
  exit 1
fi
grep -q "allowBackup" <<<"$out" || { echo "FAIL: check failed without naming allowBackup" >&2; echo "$out" >&2; exit 1; }
echo "OK mergedManifest_allowBackupTrueFixture_checkFails"
