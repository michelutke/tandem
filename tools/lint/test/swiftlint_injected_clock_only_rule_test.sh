#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fixture="$repo_root/tools/lint/fixtures/swift/InjectedClockOnlyFixture.swift"

if swiftlint lint --strict --config "$repo_root/macos/.swiftlint.yml" "$fixture"; then
  echo "FAIL: expected injected_clock_only violation in $fixture, but swiftlint exited 0" >&2
  exit 1
fi

echo "OK: injected_clock_only rule fires on $fixture"
