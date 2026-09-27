#!/usr/bin/env bash
# E20-08 tdd:
#   ci: mergedManifest_bootReceiver_declaresReceiveBootCompleted
#
# Builds :app:assembleDebug and checks the merged manifest declares RECEIVE_BOOT_COMPLETED and a
# receiver for android.intent.action.BOOT_COMPLETED (docs/planning/backlog/phase-2.yaml E20-08).
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
MERGED_MANIFEST="$ANDROID/app/build/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml"
TEST_NAME="mergedManifest_bootReceiver_declaresReceiveBootCompleted"

cd "$ANDROID"
./gradlew -q :app:assembleDebug

[ -f "$MERGED_MANIFEST" ] || { echo "FAIL: merged manifest not found at $MERGED_MANIFEST" >&2; exit 1; }

fail() {
  echo "FAIL $TEST_NAME: $1" >&2
  exit 1
}

grep -q 'android:name="android.permission.RECEIVE_BOOT_COMPLETED"' "$MERGED_MANIFEST" ||
  fail "android.permission.RECEIVE_BOOT_COMPLETED not declared"

grep -q 'android:name="dev.tandem.app.service.BootReceiver"' "$MERGED_MANIFEST" ||
  fail "no <receiver> named dev.tandem.app.service.BootReceiver in the merged manifest"

# The <receiver .../> element and its <intent-filter> span several lines once merged/pretty
# printed; grabbing a generous window after the name attribute keeps the actions in view without
# over-matching into an unrelated component.
receiver_block="$(grep -A8 'android:name="dev.tandem.app.service.BootReceiver"' "$MERGED_MANIFEST")"
echo "$receiver_block" | grep -q 'android:name="android.intent.action.BOOT_COMPLETED"' ||
  fail "BootReceiver's <intent-filter> is missing android.intent.action.BOOT_COMPLETED"

echo "OK $TEST_NAME"
