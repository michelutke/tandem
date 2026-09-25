#!/usr/bin/env bash
# E13-11 fixtures: trust-store lookups must key on SpkiFingerprint only (invariant 3).
set -euo pipefail
cd "$(dirname "$0")/../../.."
ruby tools/lint/trust-store-invariant.rb macos/Packages/TandemStore >/dev/null \
  && echo "OK trustStoreSymbolGraph_currentApi_everyLookupTakesSpkiFingerprint"
if out=$(ruby tools/lint/trust-store-invariant.rb tools/lint/fixtures/trust-store-invariant 2>&1); then
  echo "FAIL trustStoreSymbolGraph_fixtureWithHostLookup_checkFails: check passed on bad fixture"; exit 1
fi
grep -q "host: String" <<<"$out" && echo "OK trustStoreSymbolGraph_fixtureWithHostLookup_checkFails"
