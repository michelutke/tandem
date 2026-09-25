#!/usr/bin/env bash
# E00-29 tdd:
#   ci: swiftPackageResolved_resolveChangesLockfile_jobFails
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="$REPO_ROOT/tools/lint/fixtures/swift-resolved-only/MismatchedPackage"

cleanup() {
  rm -rf "$FIXTURE/.build"
}
trap cleanup EXIT

# The fixture's Package.swift requires swift-protobuf 1.38.0; its checked-in Package.resolved
# pins 1.38.1. Resolving without letting SwiftPM touch the lockfile must fail.
if out="$(cd "$FIXTURE" && swift package resolve --only-use-versions-from-resolved-file 2>&1)"; then
  echo "FAIL swiftPackageResolved_resolveChangesLockfile_jobFails: resolve passed" >&2
  echo "$out" >&2
  exit 1
fi
grep -qi "out-of-date resolved file" <<<"$out" || {
  echo "FAIL swiftPackageResolved_resolveChangesLockfile_jobFails: unexpected error" >&2
  echo "$out" >&2
  exit 1
}
echo "OK swiftPackageResolved_resolveChangesLockfile_jobFails"

# Sanity: the real TandemProtocol package (matching manifest + Package.resolved) still resolves.
TANDEM_PROTOCOL="$REPO_ROOT/macos/Packages/TandemProtocol"
if ! out="$(cd "$TANDEM_PROTOCOL" && swift package resolve --only-use-versions-from-resolved-file 2>&1)"; then
  echo "FAIL: TandemProtocol (real package) should resolve cleanly" >&2
  echo "$out" >&2
  exit 1
fi
echo "OK swiftPackageResolved sanity check (TandemProtocol resolves cleanly)"
