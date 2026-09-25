#!/usr/bin/env bash
set -uo pipefail

macos_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=()
for package_dir in "$macos_dir"/Packages/*/; do
  package_name="$(basename "$package_dir")"
  if [ ! -f "$package_dir/Package.swift" ]; then
    continue
  fi
  echo "== swift test: $package_name =="
  # E00-29: never let CI silently re-resolve a package to a version outside Package.resolved.
  if ! (cd "$package_dir" && swift test --only-use-versions-from-resolved-file); then
    failures+=("$package_name")
  fi
done

if [ "${#failures[@]}" -gt 0 ]; then
  echo "swift test failed for: ${failures[*]}" >&2
  exit 1
fi

echo "swift test passed for all local packages"
