#!/usr/bin/env bash
set -uo pipefail

# E10-14 tdd:
#   ci: keyMaterialCheck_secKeyOutsideTandemCryptoFixture_exitsNonZero
#   ci: keyMaterialCheck_hmacOutsideCryptoModuleFixture_exitsNonZero (Swift side; the Kotlin side
#   of this same tdd entry is KeyMaterialOnlyInCryptoTest.keyMaterialCheck_hmacOutsideCryptoModuleFixture_exitsNonZero)
#   ci: keyMaterialCheck_keychainStoreUsageFromTandemStore_exitsZero
#
# Fixtures are permanent files under tools/lint-fixtures/key-material/ (E10-14's acceptance: "no
# add-and-revert"). `keyMaterialCheck_currentTree_exitsZero` (Swift side) is the real
# tools/lint/swiftlint-check.sh run with TandemCrypto/TandemTestSupport excluded from this rule
# (macos/.swiftlint.yml).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
config="$repo_root/macos/.swiftlint.yml"
fixtures="$repo_root/tools/lint-fixtures/key-material"
fail=0

if swiftlint lint --strict --config "$config" "$fixtures/seckey-outside-tandemcrypto/SecKeyFixture.swift"; then
  echo "FAIL keyMaterialCheck_secKeyOutsideTandemCryptoFixture_exitsNonZero: swiftlint exited 0" >&2
  fail=1
else
  echo "OK keyMaterialCheck_secKeyOutsideTandemCryptoFixture_exitsNonZero"
fi

if swiftlint lint --strict --config "$config" "$fixtures/hmac-outside-crypto-module/HmacFixture.swift"; then
  echo "FAIL keyMaterialCheck_hmacOutsideCryptoModuleFixture_exitsNonZero: swiftlint exited 0" >&2
  fail=1
else
  echo "OK keyMaterialCheck_hmacOutsideCryptoModuleFixture_exitsNonZero"
fi

if ! swiftlint lint --strict --config "$config" "$fixtures/keychain-store-usage-from-tandemstore/TandemStoreFixture.swift"; then
  echo "FAIL keyMaterialCheck_keychainStoreUsageFromTandemStore_exitsZero: swiftlint exited non-zero" >&2
  fail=1
else
  echo "OK keyMaterialCheck_keychainStoreUsageFromTandemStore_exitsZero"
fi

exit "$fail"
