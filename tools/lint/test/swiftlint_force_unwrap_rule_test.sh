#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fixture="$repo_root/tools/lint/fixtures/swift/ForceUnwrapFixture.swift"

if swiftlint lint --strict --config "$repo_root/macos/.swiftlint.yml" "$fixture"; then
  echo "FAIL: expected force_unwrapping violation in $fixture, but swiftlint exited 0" >&2
  exit 1
fi

echo "OK: force_unwrapping rule fires on $fixture"
