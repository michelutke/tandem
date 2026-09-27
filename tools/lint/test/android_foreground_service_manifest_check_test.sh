#!/usr/bin/env bash
# E20-02 tdd:
#   ci: mergedManifest_tandemService_declaresConnectedDeviceTypeAndPermissions
#
# Builds :app:assembleDebug and checks the merged manifest declares TandemService with
# foregroundServiceType="connectedDevice" and both the FOREGROUND_SERVICE_CONNECTED_DEVICE and
# CHANGE_NETWORK_STATE permissions (the Android 14 connectedDevice foreground-service requirement,
# docs/planning/backlog/phase-2.yaml E20-02).
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
MERGED_MANIFEST="$ANDROID/app/build/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml"
TEST_NAME="mergedManifest_tandemService_declaresConnectedDeviceTypeAndPermissions"

cd "$ANDROID"
./gradlew -q :app:assembleDebug

[ -f "$MERGED_MANIFEST" ] || { echo "FAIL: merged manifest not found at $MERGED_MANIFEST" >&2; exit 1; }

fail() {
  echo "FAIL $TEST_NAME: $1" >&2
  exit 1
}

grep -q 'android:name="dev.tandem.app.service.TandemService"' "$MERGED_MANIFEST" ||
  fail "no <service> named dev.tandem.app.service.TandemService in the merged manifest"

# The <service .../> element is a single self-closing tag across a few lines once merged/pretty
# printed; grabbing the 4 lines after the name attribute keeps the other attributes in view
# without over-matching into an unrelated component.
service_block="$(grep -A4 'android:name="dev.tandem.app.service.TandemService"' "$MERGED_MANIFEST")"
echo "$service_block" | grep -q 'android:foregroundServiceType="connectedDevice"' ||
  fail "TandemService is missing android:foregroundServiceType=\"connectedDevice\""

grep -q 'android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"' "$MERGED_MANIFEST" ||
  fail "android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE not declared"

grep -q 'android:name="android.permission.CHANGE_NETWORK_STATE"' "$MERGED_MANIFEST" ||
  fail "android.permission.CHANGE_NETWORK_STATE not declared"

echo "OK $TEST_NAME"
