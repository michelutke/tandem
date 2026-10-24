#!/usr/bin/env bash
# E71-11: runs tools/release-audit/verify-release-signing.rb with the real apksigner against the
# APKs `./gradlew build` produced (android.yml). Without the release environment the release APK
# is unsigned and must fail; the debug APK carries the Android Debug certificate and must fail; the
# same release APK signed with a throwaway non-debug key must pass.
#
#   tools/release-audit/test/android_release_signing_test.sh   # after (cd android && ./gradlew build)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
VERIFY="$ROOT/tools/release-audit/verify-release-signing.rb"
export APKSIGNER="${APKSIGNER:-$(ls -d "$ANDROID_HOME"/build-tools/*/ | sort -V | tail -n1)apksigner}"
release_apk="$(find "$ROOT/android/app/build/outputs/apk/release" -name '*.apk' | head -n1)"
debug_apk="$(find "$ROOT/android/app/build/outputs/apk/debug" -name '*.apk' | head -n1)"
[ -f "$release_apk" ] && [ -f "$debug_apk" ] || { echo "build the debug and release APKs first" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

expect() { # expect <pass|fail> <name> <args...>
  local want="$1" name="$2"; shift 2
  if ruby "$VERIFY" "$@" > "$work/out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name (expected $want, got $got)"; cat "$work/out"; failures=$((failures + 1))
  fi
}

expect fail releaseSigningCheck_unsignedApk_apksignerVerifyFails apk "$release_apk"
expect fail releaseSigningCheck_apkSignedWithDebugKey_exitsNonZero apk "$debug_apk"

keytool -genkeypair -keystore "$work/test.jks" -storepass test-only -keypass test-only -alias tandem \
  -keyalg EC -groupname secp256r1 -validity 2 -dname "CN=Tandem CI Test" > /dev/null 2>&1
cp "$release_apk" "$work/signed.apk"
"$APKSIGNER" sign --ks "$work/test.jks" --ks-pass pass:test-only --ks-key-alias tandem "$work/signed.apk"
expect pass releaseSigningCheck_apkSignedWithNonDebugKey_exitsZero apk "$work/signed.apk"

exit "$failures"
