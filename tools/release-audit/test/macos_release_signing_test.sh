#!/usr/bin/env bash
# E71-11: runs tools/release-audit/verify-release-signing.rb with the real codesign and stapler
# against copies of the Release .app macos.yml builds unsigned. Unsigned must fail, ad hoc signed
# must pass, a tampered signed copy must fail, and --notarized must fail without a stapled ticket.
#
#   tools/release-audit/test/macos_release_signing_test.sh [path/to/TandemApp.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
VERIFY="$ROOT/tools/release-audit/verify-release-signing.rb"
APP="${1:-$ROOT/macos/build/release/Build/Products/Release/TandemApp.app}"
[ -d "$APP" ] || { echo "$APP not found; run the Release build first" >&2; exit 1; }

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

ditto "$APP" "$work/unsigned/TandemApp.app"
find "$work/unsigned/TandemApp.app" -type f -perm +111 -exec codesign --remove-signature {} \; 2>/dev/null || true
rm -rf "$work/unsigned/TandemApp.app/Contents/_CodeSignature"
expect fail releaseSigningCheck_unsignedMacApp_codesignVerifyFails mac-app "$work/unsigned/TandemApp.app"

ditto "$APP" "$work/signed/TandemApp.app"
codesign --force --deep --sign - "$work/signed/TandemApp.app"
expect pass releaseSigningCheck_adHocSignedMacApp_exitsZero mac-app "$work/signed/TandemApp.app"
expect fail releaseSigningCheck_notarizationEnabledWithoutTicket_staplerValidateFails mac-app "$work/signed/TandemApp.app" --notarized

ditto "$work/signed/TandemApp.app" "$work/tampered/TandemApp.app"
printf '\n' >> "$work/tampered/TandemApp.app/Contents/Info.plist"
expect fail releaseSigningCheck_tamperedMacApp_codesignVerifyFails mac-app "$work/tampered/TandemApp.app"

exit "$failures"
