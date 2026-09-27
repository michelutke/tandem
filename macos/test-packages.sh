#!/usr/bin/env bash
set -uo pipefail
set -m

macos_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_timeout_seconds=900

failures=()
for package_dir in "$macos_dir"/Packages/*/; do
  package_name="$(basename "$package_dir")"
  if [ ! -f "$package_dir/Package.swift" ]; then
    continue
  fi
  echo "== swift test: $package_name =="
  # E00-29: never let CI silently re-resolve a package to a version outside Package.resolved.
  (cd "$package_dir" && exec swift test --only-use-versions-from-resolved-file) &
  test_pid=$!

  timed_out=0
  SECONDS=0
  while kill -0 "$test_pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$package_timeout_seconds" ]; then
      timed_out=1
      break
    fi
    sleep 1
  done

  if [ "$timed_out" -eq 1 ]; then
    echo "swift test TIMED OUT after ${package_timeout_seconds}s: $package_name" >&2
    # Kill the whole process group, not just the swift test parent, so no
    # stray swiftpm-testing-helper processes are left running.
    kill -TERM -- "-$test_pid" 2>/dev/null
    sleep 2
    kill -KILL -- "-$test_pid" 2>/dev/null
    wait "$test_pid" 2>/dev/null
    failures+=("$package_name (TIMED OUT after ${package_timeout_seconds}s)")
    continue
  fi

  wait "$test_pid"
  status=$?
  if [ "$status" -ne 0 ]; then
    failures+=("$package_name")
  fi
done

if [ "${#failures[@]}" -gt 0 ]; then
  echo "swift test failed for: ${failures[*]}" >&2
  exit 1
fi

echo "swift test passed for all local packages"
