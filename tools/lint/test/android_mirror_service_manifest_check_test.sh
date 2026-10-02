#!/usr/bin/env bash
# E61-02 tdd:
#   ci: mirrorServiceManifest_foregroundServiceType_includesMediaProjection
#
# Builds :app:assembleDebug and checks the merged manifest declares MirrorCaptureService with
# foregroundServiceType="mediaProjection" and the FOREGROUND_SERVICE_MEDIA_PROJECTION permission
# (the Android 14 requirement, docs/planning/backlog/phase-6.yaml E61-02).
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
MERGED_MANIFEST="$ANDROID/app/build/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml"
TEST_NAME="mirrorServiceManifest_foregroundServiceType_includesMediaProjection"

cd "$ANDROID"
./gradlew -q :app:assembleDebug

[ -f "$MERGED_MANIFEST" ] || { echo "FAIL: merged manifest not found at $MERGED_MANIFEST" >&2; exit 1; }

fail() {
  echo "FAIL $TEST_NAME: $1" >&2
  exit 1
}

grep -q 'android:name="dev.tandem.feature.mirror.MirrorCaptureService"' "$MERGED_MANIFEST" ||
  fail "no <service> named dev.tandem.feature.mirror.MirrorCaptureService in the merged manifest"

service_block="$(grep -A4 'android:name="dev.tandem.feature.mirror.MirrorCaptureService"' "$MERGED_MANIFEST")"
echo "$service_block" | grep -q 'android:foregroundServiceType="mediaProjection"' ||
  fail "MirrorCaptureService is missing android:foregroundServiceType=\"mediaProjection\""

grep -q 'android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"' "$MERGED_MANIFEST" ||
  fail "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION not declared"

echo "OK $TEST_NAME"
