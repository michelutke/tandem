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
  if ! (cd "$package_dir" && swift test); then
    failures+=("$package_name")
  fi
done

if [ "${#failures[@]}" -gt 0 ]; then
  echo "swift test failed for: ${failures[*]}" >&2
  exit 1
fi

echo "swift test passed for all local packages"
