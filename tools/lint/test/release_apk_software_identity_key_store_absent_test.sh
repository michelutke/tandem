#!/usr/bin/env bash
# E10-15 tdd:
#   ci: releaseApk_softwareKeyStoreClass_absentFromDex
set -euo pipefail
ANDROID="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../android" && pwd)"
cd "$ANDROID"

./gradlew -q :app:assembleRelease

APK="$(find app/build/outputs/apk/release -name '*.apk' | head -n1)"
if [ -z "$APK" ]; then
  echo "FAIL: no release APK produced by :app:assembleRelease" >&2
  exit 1
fi

DEX_DIR="$(mktemp -d)"
trap 'rm -rf "$DEX_DIR"' EXIT
unzip -oq "$APK" -d "$DEX_DIR"
DEX_FILES=()
while IFS= read -r dex; do DEX_FILES+=("$dex"); done < <(find "$DEX_DIR" -name '*.dex')
if [ "${#DEX_FILES[@]}" -eq 0 ]; then
  # R8 removed all code (the app has no entry points yet), so nothing can leak.
  echo "OK releaseApk_softwareKeyStoreClass_absentFromDex (release APK contains no dex)"
  exit 0
fi

# Class/type names are stored as contiguous MUTF-8 strings in the dex string pool, so a plain
# binary grep on the extracted dex files finds them directly (no dexdump/d8 dependency needed).
if grep -aq "SoftwareIdentityKeyStore" "${DEX_FILES[@]}"; then
  echo "FAIL: SoftwareIdentityKeyStore class found in the release APK ($APK)" >&2
  exit 1
fi
echo "OK releaseApk_softwareKeyStoreClass_absentFromDex"
